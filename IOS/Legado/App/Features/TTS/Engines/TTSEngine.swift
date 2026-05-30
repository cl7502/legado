import Foundation

struct AudioChunk {
    let samples: [Float]
    let sampleRate: Int
}

struct VoiceConfig {
    let id: String           // 角色槽位 ID，如 "narrator"
    let speakerId: Int       // Kokoro speaker index
    let displayName: String
}

struct SpeakingStyle {
    var rateMultiplier: Float    = 1.0
    var pitchOffset: Float       = 0.0
    var volumeMultiplier: Float  = 1.0

    static let normal = SpeakingStyle()
}

protocol TTSEngine: AnyObject {
    var isReady: Bool { get }
    func warmup() async
    func synthesize(
        text: String,
        voice: VoiceConfig,
        style: SpeakingStyle
    ) async throws -> AudioChunk
}

enum TTSError: Error {
    case engineNotReady
    case modelNotFound(String)
    case synthesizeFailed(String)
}
