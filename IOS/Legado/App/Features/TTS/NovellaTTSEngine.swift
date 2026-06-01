import Foundation
import AVFoundation
import Combine
import MediaPlayer

/// 高质量 TTS 主控协调器。
/// ⚠️ 不能标注 @MainActor：ONNX 推理必须在后台线程。
/// @Published 属性通过 DispatchQueue.main.async 更新。
final class NovellaTTSEngine: ObservableObject, TTSProtocol, @unchecked Sendable {

    static let shared = NovellaTTSEngine()

    // MARK: - TTSProtocol 公开状态
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var speakingRange: NSRange? = nil
    @Published private(set) var remainingSeconds: Int? = nil
    var selectedVoice: AVSpeechSynthesisVoice? = nil   // AVSpeech 协议占位，ZipVoice 不使用

    // MARK: - 音色选择
    /// 从 preset_voices.json 加载的所有可用音色
    let availableVoices: [VoiceConfig]

    /// 当前选中的音色 ID（对应 VoiceConfig.id）
    @Published private(set) var selectedVoiceId: String

    /// 切换音色；ZipVoice 逐句合成，下一句自动生效，无需重启流水线
    func selectVoice(id: String) {
        guard let voice = availableVoices.first(where: { $0.id == id }) else { return }
        narratorVoice = voice
        selectedVoiceId = id
        ReaderSettings.shared.ttsZipVoiceId = id
    }

    // MARK: - 私有
    private let engine: SherpaZipVoiceEngine
    private let pipeline   = AudioPipeline()
    private let normalizer = TextNormalizer()
    private let splitter   = SentenceSplitter()

    private var sentenceQueue:    [SentenceUnit] = []
    private var currentIndex      = 0
    private var onChapterFinish:  (() -> Void)?
    private var originalText      = ""
    private var currentBookName   = ""
    private var currentChapterTitle = ""
    private var generationTask:   Task<Void, Never>?
    private var timerTask:        Task<Void, Never>?

    private var narratorVoice: VoiceConfig

    private static func loadPresetVoices() -> [VoiceConfig] {
        guard let url = Bundle.main.url(forResource: "preset_voices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        struct Entry: Decodable {
            let id, displayName, refAudioFile, refText: String
            let basePitch, baseRate: Float
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.map { VoiceConfig(id: $0.id, displayName: $0.displayName,
                                         refAudioFile: $0.refAudioFile, refText: $0.refText,
                                         basePitch: $0.basePitch, baseRate: $0.baseRate) }
    }

    private init() {
        let voices = NovellaTTSEngine.loadPresetVoices()
        let savedId = ReaderSettings.shared.ttsZipVoiceId
        let initial = voices.first(where: { $0.id == savedId })
            ?? voices.first
            ?? VoiceConfig(id: "narrator", displayName: "旁白",
                           refAudioFile: "ref_narrator_f.wav",
                           refText: "各位村民，大家新年好！近期，湖北省武汉市等多个地区")
        availableVoices = voices
        narratorVoice = initial
        selectedVoiceId = initial.id

        let refsDir = ModelManager.voiceRefsDir() ?? ""
        engine = SherpaZipVoiceEngine(voiceRefsDir: refsDir)
        pipeline.onSentenceComplete = { [weak self] sentence in
            self?.onSentencePlayed(sentence)
        }
        Task { await self.setupOnLaunch() }
    }

    private func setupOnLaunch() async {
        do { try pipeline.setup() }
        catch { print("❌ [NovellaTTS] AudioPipeline setup 失败: \(error)") }
        setupAudioSession()
        setupRemoteCommandCenter()
        await engine.warmup()
    }

    // MARK: - TTSProtocol

    func speak(_ text: String, bookName: String, chapterTitle: String,
               onFinish: @escaping () -> Void) {
        stopInternal()

        // 每次朗读前重激活 AVAudioSession，防止被其他音频/中断后 session 变为不活跃
        // 这是 AudioPipeline.engine.start() 失败（TTS 无声）的主要原因之一
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

        originalText          = text
        currentBookName       = bookName
        currentChapterTitle   = chapterTitle
        onChapterFinish       = onFinish

        // ⚡ split 用原始文本，保持 charOffset 坐标系一致
        sentenceQueue = splitter.split(text, baseOffset: 0)
        currentIndex  = 0
        isStopped     = false   // 允许 enqueue

        DispatchQueue.main.async {
            self.isPlaying  = true
            self.isSpeaking = true
        }
        updateNowPlayingInfo()
        startGenerationPipeline()
    }

    func pause() {
        pipeline.pause()
        generationTask?.cancel()
        DispatchQueue.main.async {
            self.isPlaying  = false
            self.isSpeaking = false
        }
    }

    func resume() {
        do { try pipeline.resume() }
        catch { print("❌ [NovellaTTS] resume 失败: \(error)"); return }
        DispatchQueue.main.async {
            self.isPlaying  = true
            self.isSpeaking = true
        }
        startGenerationPipeline()
    }

    func stop() {
        cancelTimer()
        stopInternal()
    }

    func restartForSettingChange() {
        guard isPlaying || isSpeaking, !originalText.isEmpty else { return }
        let t = originalText; let b = currentBookName
        let c = currentChapterTitle; let cb = onChapterFinish ?? {}
        speak(t, bookName: b, chapterTitle: c, onFinish: cb)
    }

    func startTimer(minutes: Int) {
        timerTask?.cancel()
        let secs = minutes * 60
        DispatchQueue.main.async { self.remainingSeconds = secs }
        timerTask = Task { [weak self] in
            var remaining = secs          // 局部变量，不跨线程共享
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                let r = remaining
                DispatchQueue.main.async { self?.remainingSeconds = r }
            }
            // stop() 修改 sentenceQueue/currentIndex，必须在主线程执行以避免竞态
            DispatchQueue.main.async { self?.stop() }
        }
    }

    func cancelTimer() {
        timerTask?.cancel(); timerTask = nil
        DispatchQueue.main.async { self.remainingSeconds = nil }
    }

    // MARK: - 流水线

    private func startGenerationPipeline() {
        generationTask?.cancel()
        // Capture on calling thread (main) — value types, no race
        let startIdx      = currentIndex
        let queueSnap     = sentenceQueue
        let normalizer    = self.normalizer
        let narratorVoice = self.narratorVoice
        // ⚡ Task.detached：ONNX 推理在后台线程，不阻塞 MainActor
        generationTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let endIdx = min(startIdx + 2, queueSnap.count)
            for idx in startIdx..<endIdx {
                guard !Task.isCancelled else { return }
                let sentence = queueSnap[idx]
                // ⚡ TextNormalizer 只在此处对送入 TTS 的文本应用
                let ttsText = normalizer.normalize(sentence.text)
                do {
                    let chunk = try await self.engine.synthesize(
                        text: ttsText, voice: narratorVoice, style: .normal)
                    let voiceStyle = SpeakingStyle(
                        rateMultiplier:  1.0,
                        pitchOffset:     narratorVoice.basePitch,
                        volumeMultiplier: 1.0
                    )
                    await MainActor.run {
                        // 飞行中的 synthesis 完成时若已调用 stop()，丢弃结果
                        guard !self.isStopped else { return }
                        self.pipeline.enqueue(chunk: chunk, sentence: sentence, style: voiceStyle)
                    }
                } catch {
                    print("❌ [NovellaTTS] 合成失败 idx=\(idx): \(error)")
                }
            }
        }
    }

    private func onSentencePlayed(_ sentence: SentenceUnit) {
        DispatchQueue.main.async {
            self.speakingRange = NSRange(location: sentence.charOffset,
                                        length: sentence.charLength)
        }
        currentIndex += 1
        if currentIndex >= sentenceQueue.count {
            DispatchQueue.main.async {
                self.isPlaying = false; self.isSpeaking = false
                self.speakingRange = nil
            }
            onChapterFinish?()
        } else {
            startGenerationPipeline()
        }
    }

    private var isStopped = true   // 飞行中的 synthesis 完成后检查此 flag，阻止 enqueue

    private func stopInternal() {
        isStopped = true                           // 同步置位，Task 完成后 enqueue 会被拦截
        generationTask?.cancel(); generationTask = nil
        pipeline.stop()
        sentenceQueue = []; currentIndex = 0; onChapterFinish = nil
        DispatchQueue.main.async {
            self.isPlaying = false; self.isSpeaking = false
            self.speakingRange = nil; self.remainingSeconds = nil
        }
    }

    // MARK: - Audio Session + Now Playing
    private func setupAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        // removeTarget(nil) 先清除所有已注册 handler，防止多次调用累积注册
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.playCommand.addTarget  { [weak self] _ in self?.resume(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause();  return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            isPlaying ? pause() : resume(); return .success
        }
    }

    private func updateNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:             currentChapterTitle,
            MPMediaItemPropertyArtist:            currentBookName,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }
}
