import Foundation
import AVFoundation

/// TTSManager（系统TTS）和 NovellaTTSEngine（高质量TTS）共用的公开接口。
/// ReaderViewModel 和 ReaderView 只依赖此协议，切换引擎无需改调用代码。
protocol TTSProtocol: AnyObject {
    /// 正在朗读且未暂停（UI 面板按钮状态依据此值显示"暂停"/"继续"）
    var isPlaying: Bool { get }
    var speakingRange: NSRange? { get }
    var remainingSeconds: Int? { get }
    /// 朗读会话是否激活（含暂停态），用于判断是否有进行中的朗读任务
    var isSpeaking: Bool { get }

    /// AVSpeechSynthesizer 专用，NovellaTTSEngine 实现为 nil（Phase 1a 暂不使用）
    /// 未来 Phase 2 可删除此属性，由 VoiceRegistry 统一管理
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
