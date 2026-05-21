import Foundation
import AVFoundation
import MediaPlayer

/// 工业级 TTS 管理器
/// 目标：支持后台播放、锁屏控制、自动连读、语速调节
class TTSManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    static let shared = TTSManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isSpeaking = false
    @Published var currentText: String = ""
    @Published var rate: Float = 0.5 // 0.0 ~ 1.0
    @Published var pitch: Float = 1.0 // 0.5 ~ 2.0
    
    private var onChapterFinish: (() -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
        setupRemoteCommandCenter()
    }
    
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
        
        // 自动识别语言 (默认为中文)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        
        synthesizer.speak(utterance)
        isSpeaking = true
        
        updateNowPlayingInfo(title: chapterTitle, artist: bookName)
    }
    
    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
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
        // 章节朗读结束，触发回调进行下一章连读
        onChapterFinish?()
    }
}
