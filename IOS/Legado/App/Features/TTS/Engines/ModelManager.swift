import Foundation

struct ModelManager {

    enum Model {
        case zipVoiceDistillInt8   // 主力模型：ZipVoice 中英双语
    }

    static let zipVoiceDirName    = "sherpa-onnx-zipvoice-distill-int8-zh-en-emilia"
    static let zipVoiceEncoder    = "encoder.int8.onnx"
    static let zipVoiceDecoder    = "decoder.int8.onnx"
    static let voiceRefsDirName   = "VoiceReferences"

    static func modelDir(for model: Model) -> String? {
        switch model {
        case .zipVoiceDistillInt8:
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let docsPath = docs.appendingPathComponent("TTS/\(zipVoiceDirName)").path
            if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
            return Bundle.main.path(forResource: zipVoiceDirName, ofType: nil)
        }
    }

    static func voiceRefsDir() -> String? {
        Bundle.main.path(forResource: voiceRefsDirName, ofType: nil)
    }

    static func isAvailable(_ model: Model) -> Bool {
        guard let dir = modelDir(for: model) else { return false }
        return FileManager.default.fileExists(atPath: "\(dir)/\(zipVoiceEncoder)")
    }
}
