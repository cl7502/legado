import Foundation

#if SHERPA_ONNX_ENABLED

/// Sherpa-ONNX + ZipVoice 零样本声音克隆引擎。
/// synthesize() 在 Task.detached 中调用，不应在 MainActor 运行。
final class SherpaZipVoiceEngine: TTSEngine {

    private var tts: SherpaOnnxOfflineTtsWrapper?
    private(set) var isReady = false
    private let voiceRefsDir: String

    init(voiceRefsDir: String) {
        self.voiceRefsDir = voiceRefsDir
    }

    func warmup() async {
        guard let dir = ModelManager.modelDir(for: .zipVoiceDistillInt8) else {
            print("❌ [ZipVoice] 模型目录未找到"); return
        }
        let encoder   = "\(dir)/\(ModelManager.zipVoiceEncoder)"
        let decoder   = "\(dir)/\(ModelManager.zipVoiceDecoder)"
        let vocoder   = "\(dir)/vocos_24khz.onnx"
        let tokens    = "\(dir)/tokens.txt"
        let lexicon   = "\(dir)/lexicon.txt"
        let dataDir   = "\(dir)/espeak-ng-data"

        for path in [encoder, decoder, vocoder, tokens] {
            guard FileManager.default.fileExists(atPath: path) else {
                print("❌ [ZipVoice] 文件不存在: \(path)"); return
            }
        }

        let zipConfig = sherpaOnnxOfflineTtsZipvoiceModelConfig(
            tokens:  tokens,
            encoder: encoder,
            decoder: decoder,
            vocoder: vocoder,
            dataDir: dataDir,
            lexicon: lexicon
        )
        let modelConfig = sherpaOnnxOfflineTtsModelConfig(zipvoice: zipConfig)
        let config = sherpaOnnxOfflineTtsConfig(
            model:           modelConfig,
            ruleFsts:        "",
            ruleFars:        "",
            maxNumSentences: 1
        )

        tts = withUnsafePointer(to: config) { SherpaOnnxOfflineTtsWrapper(config: $0) }
        isReady = tts != nil

        if isReady {
            print("✅ [ZipVoice] 引擎预热完成，Speaker 数: \(SherpaOnnxOfflineTtsNumSpeakers(tts!.tts))")
        } else {
            print("❌ [ZipVoice] 引擎初始化失败")
        }
    }

    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        guard let tts, isReady else { throw TTSError.engineNotReady }

        // 加载参考音频
        let refPath = "\(voiceRefsDir)/\(voice.refAudioFile)"
        guard FileManager.default.fileExists(atPath: refPath) else {
            throw TTSError.refAudioNotFound(refPath)
        }
        guard let (refSamples, refSampleRate) = WavReader.load(path: refPath) else {
            throw TTSError.refAudioLoadFailed(voice.refAudioFile)
        }

        // 合并 VoiceConfig 的基础参数和 SpeakingStyle 的调整
        var genConfig = SherpaOnnxGenerationConfigSwift()
        genConfig.referenceAudio      = refSamples
        genConfig.referenceSampleRate = refSampleRate
        genConfig.referenceText       = voice.refText
        genConfig.speed               = style.rateMultiplier * voice.baseRate
        genConfig.numSteps            = 32   // ZipVoice Flow Matching 步数（高质量）

        let audio = tts.generateWithConfig(text: text, config: genConfig,
                                           callback: nil, arg: nil)
        let samples = audio.samples
        guard !samples.isEmpty else {
            throw TTSError.synthesizeFailed("ZipVoice generate 返回空样本，text=\(text.prefix(20))")
        }
        return AudioChunk(samples: samples, sampleRate: Int(audio.sampleRate))
    }
}

#else

final class SherpaZipVoiceEngine: TTSEngine {
    private(set) var isReady = false
    init(voiceRefsDir: String) {}
    func warmup() async {}
    func synthesize(text: String, voice: VoiceConfig,
                    style: SpeakingStyle) async throws -> AudioChunk {
        throw TTSError.engineNotReady
    }
}

#endif
