#if DEBUG
import Foundation
import AVFoundation

/// 批量生成所有预设声音的试听样本，供人工试听后验证效果。
/// 使用方式：在 LegadoApp.swift 的 #if DEBUG .task {} 中调用 generateAll()，
/// 输出 WAV 文件到 Documents/audition/，取出后用 QuickTime 逐一试听。
final class SpeakerAuditionHelper {

    static func generateAll() async {
        guard let refsDir = ModelManager.voiceRefsDir() else {
            print("❌ [Audition] VoiceReferences 目录未找到")
            return
        }
        let engine = SherpaZipVoiceEngine(voiceRefsDir: refsDir)
        await engine.warmup()
        guard engine.isReady else {
            print("❌ [Audition] 引擎未就绪，请确认模型文件已加入 Bundle")
            return
        }

        let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audition")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sampleText = "林峰抬起头，看向远方的天际，心中涌起一阵难以言说的情绪。她轻声说道，我等你很久了。"

        // 加载 preset_voices.json
        guard let jsonURL = Bundle.main.url(forResource: "preset_voices", withExtension: "json"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let voices = try? JSONDecoder().decode([PresetVoiceEntry].self, from: jsonData) else {
            print("❌ [Audition] 无法加载 preset_voices.json")
            return
        }

        for entry in voices {
            let voice = VoiceConfig(
                id: entry.id,
                displayName: entry.displayName,
                refAudioFile: entry.refAudioFile,
                refText: entry.refText,
                basePitch: entry.basePitch,
                baseRate: entry.baseRate
            )
            do {
                let chunk = try await engine.synthesize(text: sampleText,
                                                        voice: voice, style: .normal)
                let wavURL = outputDir.appendingPathComponent("\(entry.id).wav")
                writeWAV(samples: chunk.samples, sampleRate: chunk.sampleRate, to: wavURL)
                print("✅ \(entry.displayName)(\(entry.id)) → \(wavURL.lastPathComponent)")
            } catch {
                print("⚠️ \(entry.id) 合成失败: \(error)")
            }
        }
        print("🎵 试听文件已生成到 Documents/audition/，共 \(voices.count) 个")
    }

    private struct PresetVoiceEntry: Decodable {
        let id: String
        let displayName: String
        let refAudioFile: String
        let refText: String
        let basePitch: Float
        let baseRate: Float
    }

    private static func writeWAV(samples: [Float], sampleRate: Int, to url: URL) {
        let numSamples = samples.count
        let dataSize   = numSamples * 2
        var header = Data()
        func u32(_ v: UInt32) {
            var x = v.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        func u16(_ v: UInt16) {
            var x = v.littleEndian
            header.append(contentsOf: withUnsafeBytes(of: &x) { Array($0) })
        }
        header.append(contentsOf: "RIFF".utf8)
        u32(UInt32(36 + dataSize))
        header.append(contentsOf: "WAVEfmt ".utf8)
        u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2); u16(16)
        header.append(contentsOf: "data".utf8)
        u32(UInt32(dataSize))

        var pcm = Data(capacity: dataSize)
        for s in samples {
            // 防止 NaN/Inf 导致 Int 转换崩溃
            let safe = (s.isNaN || s.isInfinite) ? 0.0 : s
            var v = Int16(max(-32768, min(32767, Int(safe * 32767))))
            pcm.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }
        try? (header + pcm).write(to: url)
    }
}
#endif
