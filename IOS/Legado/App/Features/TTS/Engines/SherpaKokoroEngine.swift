import Foundation

#if SHERPA_ONNX_ENABLED

/// Sherpa-ONNX + Kokoro TTS 引擎封装。
/// synthesize() 设计为在后台 Task.detached 中调用，不应在 MainActor 运行。
final class SherpaKokoroEngine: TTSEngine {

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private(set) var isReady = false

    func warmup() async {
        guard let dir = ModelManager.modelDir(for: .kokoroInt8MultiLangV1_1) else {
            print("❌ [SherpaKokoro] 模型目录未找到")
            return
        }

        let modelPath   = "\(dir)/\(ModelManager.kokoroModelFile)"
        let voicesPath  = "\(dir)/\(ModelManager.kokoroVoicesFile)"
        let tokensPath  = "\(dir)/tokens.txt"
        let dataDirPath = "\(dir)/espeak-ng-data"

        // 验证关键文件存在
        for path in [modelPath, voicesPath, tokensPath] {
            guard FileManager.default.fileExists(atPath: path) else {
                print("❌ [SherpaKokoro] 文件不存在: \(path)")
                return
            }
        }

        let kokoroConfig = sherpaOnnxOfflineTtsKokoroModelConfig(
            model:       modelPath,
            voices:      voicesPath,
            tokens:      tokensPath,
            dataDir:     dataDirPath,
            lengthScale: 1.0,
            dictDir:     "",
            lexicon:     ""
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(kokoro: kokoroConfig)
        let config = sherpaOnnxOfflineTtsConfig(
            model:           modelConfig,
            ruleFsts:        "",
            ruleFars:        "",
            maxNumSentences: 1
        )

        tts = withUnsafePointer(to: config) { SherpaOnnxOfflineTtsWrapper(config: $0) }
        isReady = tts != nil

        if isReady {
            _ = tts?.generate(text: "你好", sid: 0, speed: 1.0)
            print("✅ [SherpaKokoro] 预热完成")
        } else {
            print("❌ [SherpaKokoro] 引擎初始化失败")
        }
    }

    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        guard let tts, isReady else { throw TTSError.engineNotReady }
        let audio = tts.generate(
            text:  text,
            sid:   voice.speakerId,
            speed: style.rateMultiplier
        )
        let samples = audio.samples
        guard !samples.isEmpty else {
            throw TTSError.synthesizeFailed("Kokoro generate 返回空样本，text=\(text.prefix(20))")
        }
        return AudioChunk(
            samples:    samples,
            sampleRate: Int(audio.sampleRate)
        )
    }
}

#else

/// 未启用 Sherpa-ONNX 时的空实现，保证其他代码可以引用 SherpaKokoroEngine 类型。
final class SherpaKokoroEngine: TTSEngine {
    private(set) var isReady = false
    func warmup() async {}
    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        throw TTSError.engineNotReady
    }
}

#endif // SHERPA_ONNX_ENABLED
