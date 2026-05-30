import Foundation
import AVFoundation

/// TTSManager（系统TTS）和 NovellaTTSEngine（高质量TTS）共用的公开接口。
/// ReaderViewModel 和 ReaderView 只依赖此协议，切换引擎无需改调用代码。
protocol TTSProtocol: AnyObject {
    var isPlaying: Bool { get }
    var speakingRange: NSRange? { get }
    var remainingSeconds: Int? { get }
    var isSpeaking: Bool { get }

    /// selectedVoice 仅 TTSManager（AVSpeechSynthesizer）使用，NovellaTTSEngine 可空实现
    var selectedVoice: AVSpeechSynthesisVoice? { get set }

    func speak(_ text: String, bookName: String, chapterTitle: String,
               onFinish: @escaping () -> Void)
    func pause()
    func resume()
    func stop()
    func startTimer(minutes: Int)
    func cancelTimer()
    func restartForSettingChange()
}
