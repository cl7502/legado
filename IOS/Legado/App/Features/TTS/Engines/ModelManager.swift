import Foundation

struct ModelManager {

    enum Model {
        case kokoroInt8MultiLangV1_1
    }

    // 实际文件名（v1.1 int8 版本）
    static let kokoroDirName = "kokoro-int8-multi-lang-v1_1"
    // 模型文件名（int8 量化版用 model.int8.onnx，非 model.onnx）
    static let kokoroModelFile = "model.int8.onnx"
    // Voices 文件（新版用 voices.bin，非 voices.json）
    static let kokoroVoicesFile = "voices.bin"

    static func modelDir(for model: Model) -> String? {
        switch model {
        case .kokoroInt8MultiLangV1_1:
            // 先检查 Documents（生产下载路径）
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let docsPath = docs.appendingPathComponent("TTS/\(kokoroDirName)").path
            if FileManager.default.fileExists(atPath: docsPath) { return docsPath }
            // 回退到 Bundle（开发阶段）
            return Bundle.main.path(forResource: kokoroDirName, ofType: nil)
        }
    }

    static func isAvailable(_ model: Model) -> Bool {
        guard let dir = modelDir(for: model) else { return false }
        // 检查关键文件存在
        return FileManager.default.fileExists(atPath: "\(dir)/\(kokoroModelFile)")
    }
}
