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

    /// 将当前朗读的小范围扩展到整句，再发布给 UI 高亮
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        let sentenceRange = expandToSentence(in: utterance.speechString, around: characterRange)
        DispatchQueue.main.async {
            self.speakingRange = sentenceRange
        }
    }

    /// 把 range 向前/后扩展到最近的句子边界（。！？…\n 等），至少覆盖整句。
    private func expandToSentence(in text: String, around range: NSRange) -> NSRange {
        let ns = text as NSString
        let len = ns.length
        // 中英文句子结束符
        let enders: Set<unichar> = [
            0x3002,  // 。
            0xFF01,  // ！
            0xFF1F,  // ？
            0x2026,  // …
            0x000A,  // \n 换行
            0x0021,  // !
            0x003F,  // ?
            0x002E,  // .
        ]
        // 向前找句子起点（上一个结束符的后一位，或文本开头）
        var start = range.location
        while start > 0 {
            if enders.contains(ns.character(at: start - 1)) { break }
            start -= 1
        }
        // 向后找句子终点（下一个结束符，含本身）
        var end = range.location + range.length
        while end < len {
            let c = ns.character(at: end)
            end += 1
            if enders.contains(c) { break }
        }
        return NSRange(location: start, length: max(0, end - start))
    }
}
