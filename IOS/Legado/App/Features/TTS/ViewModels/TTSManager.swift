import Foundation
import AVFoundation
import MediaPlayer

/// TTS 管理器
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = TTSManager()

    private let synthesizer = AVSpeechSynthesizer()

    @Published var isSpeaking = false
    @Published var currentText: String = ""

    /// 当前朗读字符范围（在 currentText 中的偏移，用于正文高亮）
    @Published private(set) var speakingRange: NSRange? = nil

    /// 用户选定的声音（nil = 系统默认）
    var selectedVoice: AVSpeechSynthesisVoice? = nil {
        didSet {
            ReaderSettings.shared.ttsVoiceIdentifier = selectedVoice?.identifier ?? ""
            restartForSettingChange()
        }
    }

    /// 当前是否正在朗读（非暂停状态）
    @Published private(set) var isPlaying: Bool = false

    /// 定时倒计时（秒），nil = 无定时
    @Published private(set) var remainingSeconds: Int? = nil

    private var timerTask: Task<Void, Never>?
    private var onChapterFinish: (() -> Void)?

    // 用于 restartForSettingChange 重启当前句
    private var currentBookName: String = ""
    private var currentChapterTitle: String = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        setupRemoteCommandCenter()
        let savedId = ReaderSettings.shared.ttsVoiceIdentifier
        if !savedId.isEmpty {
            selectedVoice = AVSpeechSynthesisVoice(identifier: savedId)
        }
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ [TTS] audio session error: \(error)")
        }
    }

    // MARK: - 朗读
    // 以下方法均由主线程（SwiftUI 按钮动作）触发，可直接同步更新 @Published 属性

    func speak(_ text: String, bookName: String, chapterTitle: String,
               onFinish: @escaping () -> Void) {
        stopSynthesizer()

        currentText         = text
        currentBookName     = bookName
        currentChapterTitle = chapterTitle
        onChapterFinish     = onFinish

        let utterance = makeUtterance(text)
        synthesizer.speak(utterance)
        isSpeaking = true
        isPlaying  = true   // 同步赋值，面板立即显示"暂停"

        updateNowPlayingInfo(title: chapterTitle, artist: bookName)
    }

    /// 语速或发音变更后，用最新设置重新朗读当前文本
    func restartForSettingChange() {
        guard isSpeaking || isPlaying, !currentText.isEmpty else { return }
        stopSynthesizer()
        let utterance = makeUtterance(currentText)
        synthesizer.speak(utterance)
        isSpeaking = true
        isPlaying  = true
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(
            max(ReaderSettings.shared.ttsRate, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        utterance.pitchMultiplier = ReaderSettings.shared.ttsPitch
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        return utterance
    }

    private func stopSynthesizer() {
        onChapterFinish = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking   = false
        isPlaying    = false   // 同步
        speakingRange = nil
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
        isPlaying  = false   // 同步
    }

    func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
        isPlaying  = true    // 同步
    }

    func stop() {
        cancelTimer()
        stopSynthesizer()
    }

    // MARK: - 定时

    func startTimer(minutes: Int) {
        cancelTimer()
        let seconds = minutes * 60
        DispatchQueue.main.async { self.remainingSeconds = seconds }
        timerTask = Task { @MainActor in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
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

    // MARK: - 锁屏控制

    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget  { [unowned self] _ in resume(); return .success }
        cc.pauseCommand.addTarget { [unowned self] _ in pause();  return .success }
        cc.togglePlayPauseCommand.addTarget { [unowned self] _ in
            isSpeaking ? pause() : resume(); return .success
        }
    }

    private func updateNowPlayingInfo(title: String, artist: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:              title,
            MPMediaItemPropertyArtist:             artist,
            MPNowPlayingInfoPropertyPlaybackRate:  1.0,
        ]
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        DispatchQueue.main.async {
            self.isPlaying = false
            self.speakingRange = nil
        }
        onChapterFinish?()
    }

    /// 当前正在朗读的字符范围（用于正文高亮）
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speakingRange = characterRange
        }
    }
}
