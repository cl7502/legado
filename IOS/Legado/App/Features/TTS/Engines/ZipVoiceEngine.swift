import Foundation

/// Phase 2 占位桩，待 ZipVoice ONNX 就绪后实现。
final class ZipVoiceEngine: TTSEngine {
    var isReady: Bool { false }
    func warmup() async {}
    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        throw TTSError.engineNotReady
    }
}

enum TTSError: Error {
    case engineNotReady
    case modelNotFound(String)
    case synthesizeFailed(String)
}
