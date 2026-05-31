import Foundation

struct AudioChunk {
    let samples: [Float]
    let sampleRate: Int
}

/// ZipVoice 零样本声音克隆的声音配置
struct VoiceConfig {
    let id: String
    let displayName: String
    let refAudioFile: String   // VoiceReferences/ 目录下的文件名
    let refText: String        // 参考音频的文字转录（必须与音频内容匹配）
    let basePitch: Float       // 基础音调偏移（cent，在 SpeakingStyle 基础上叠加）
    let baseRate: Float        // 基础语速倍数（在 SpeakingStyle 基础上叠加）

    init(id: String, displayName: String, refAudioFile: String, refText: String,
         basePitch: Float = 0.0, baseRate: Float = 1.0) {
        self.id = id; self.displayName = displayName
        self.refAudioFile = refAudioFile; self.refText = refText
        self.basePitch = basePitch; self.baseRate = baseRate
    }
}

struct SpeakingStyle {
    var rateMultiplier: Float   = 1.0
    var pitchOffset: Float      = 0.0
    var volumeMultiplier: Float = 1.0
    static let normal = SpeakingStyle()
}

protocol TTSEngine: AnyObject {
    var isReady: Bool { get }
    func warmup() async
    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk
}

enum TTSError: Error {
    case engineNotReady
    case modelNotFound(String)
    case synthesizeFailed(String)
    case refAudioNotFound(String)
    case refAudioLoadFailed(String)
}
