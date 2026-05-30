import Foundation
import AVFoundation
import MediaPlayer

/// 工业级 TTS 管理器
/// 目标：支持后台播放、锁屏控制、自动连读、语速调节、自定义语音
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = TTSManager()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var isSpeaking = false
    @Published var currentText: String = ""
    @Published var rate: Float = 0.5 // 0.0 ~ 1.0
    @Published var pitch: Float = 1.0 // 0.5 ~ 2.0

    // P2-B: 自定义语音支持（统一使用 ReaderSettings.ttsVoiceIdentifier 持久化，废弃旧 savedVoiceId）
    /// 用户选定的 AVSpeechSynthesisVoice（nil = 系统默认）
    var selectedVoice: AVSpeechSynthesisVoice? = nil {
        didSet { ReaderSettings.shared.ttsVoiceIdentifier = selectedVoice?.identifier ?? "" }
    }

    /// 当前是否正在朗读（非暂停状态）
    @Published private(set) var isPlaying: Bool = false

    /// 定时停止倒计时（秒），nil = 无定时
    @Published private(set) var remainingSeconds: Int? = nil

    private var timerTask: Task<Void, Never>?

    private var onChapterFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        setupRemoteCommandCenter()
        // 从 ReaderSettings 恢复已选声音（单一来源）
        let savedId = ReaderSettings.shared.ttsVoiceIdentifier
        if !savedId.isEmpty {
            selectedVoice = AVSpeechSynthesisVoice(identifier: savedId)
        }
    }

    // 过滤中文和英文语音
    private func loadAvailableVoices() {}

    /// 配置音频会话 (核心：支持后台)
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ [TTS Error]: Failed to set audio session category: \(error)")
        }
    }

    /// 朗读正文
    func speak(_ text: String, bookName: String, chapterTitle: String, onFinish: @escaping () -> Void) {
        stop()

        self.currentText = text
        self.onChapterFinish = onFinish

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch

        // 统一使用 selectedVoice，无则降级 zh-CN
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")

        synthesizer.speak(utterance)
        isSpeaking = true
        DispatchQueue.main.async { self.isPlaying = true }

        updateNowPlayingInfo(title: chapterTitle, artist: bookName)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
        DispatchQueue.main.async { self.isPlaying = false }
    }

    func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
        DispatchQueue.main.async { self.isPlaying = true }
    }

    func stop() {
        onChapterFinish = nil  // 先清回调，防止 didFinish 触发连读链
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        DispatchQueue.main.async {
            self.isPlaying = false
            self.remainingSeconds = nil
        }
        cancelTimer()
    }

    // MARK: - 定时停止

    /// 开始定时倒计时，到 0 时自动停止朗读
    func startTimer(minutes: Int) {
        cancelTimer()
        let seconds = minutes * 60
        DispatchQueue.main.async { self.remainingSeconds = seconds }
        timerTask = Task { @MainActor in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }   // sleep 后立即检查取消（CR-05）
                remaining -= 1
                self.remainingSeconds = remaining
            }
            self.stop()
        }
    }

    func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        DispatchQueue.main.async { self.remainingSeconds = nil }
    }

    // MARK: - 锁屏控制 (MPNowPlayingInfoCenter)

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [unowned self] _ in
            self.resume()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [unowned self] _ in
            self.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [unowned self] _ in
            if self.isSpeaking { self.pause() } else { self.resume() }
            return .success
        }
    }

    private func updateNowPlayingInfo(title: String, artist: String) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        DispatchQueue.main.async { self.isPlaying = false }
        // 章节朗读结束，触发回调进行下一章连读
        onChapterFinish?()
    }
}
