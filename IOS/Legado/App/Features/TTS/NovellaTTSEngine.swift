import Foundation
import AVFoundation
import Combine
import MediaPlayer

/// 高质量 TTS 主控协调器（Phase 1a：单一旁白声音）。
/// ⚠️ 不能标注 @MainActor：ONNX 推理必须在后台线程。
/// @Published 属性通过 DispatchQueue.main.async 更新。
final class NovellaTTSEngine: ObservableObject, TTSProtocol {

    static let shared = NovellaTTSEngine()

    // MARK: - TTSProtocol 公开状态
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var speakingRange: NSRange? = nil
    @Published private(set) var remainingSeconds: Int? = nil
    var selectedVoice: AVSpeechSynthesisVoice? = nil   // Phase 1a 不使用

    // MARK: - 私有
    private let engine     = SherpaKokoroEngine()
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

    private let narratorVoice = VoiceConfig(id: "narrator", speakerId: 0, displayName: "旁白")

    private init() {
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

        originalText          = text
        currentBookName       = bookName
        currentChapterTitle   = chapterTitle
        onChapterFinish       = onFinish

        // ⚡ split 用原始文本，保持 charOffset 坐标系一致
        sentenceQueue = splitter.split(text, baseOffset: 0)
        currentIndex  = 0

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
            var remaining = secs
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
                DispatchQueue.main.async { self?.remainingSeconds = remaining }
            }
            self?.stop()
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
                    await MainActor.run {
                        self.pipeline.enqueue(chunk: chunk, sentence: sentence, style: .normal)
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

    private func stopInternal() {
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
        cc.playCommand.addTarget  { [unowned self] _ in resume(); return .success }
        cc.pauseCommand.addTarget { [unowned self] _ in pause();  return .success }
        cc.togglePlayPauseCommand.addTarget { [unowned self] _ in
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
