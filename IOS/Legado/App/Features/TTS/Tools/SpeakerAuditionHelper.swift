#if DEBUG
import Foundation
import AVFoundation

/// 批量生成所有 Kokoro Speaker 的试听样本，供人工试听后填写 preset_voices.json。
/// 使用方式：在 LegadoApp.swift 的 #if DEBUG .task {} 中调用 generateAll()，
/// 输出 WAV 文件到 Documents/audition/，取出后用 QuickTime 逐一试听。
final class SpeakerAuditionHelper {

    static func generateAll() async {
        let engine = SherpaKokoroEngine()
        await engine.warmup()
        guard engine.isReady else {
            print("❌ [Audition] 引擎未就绪，请确认模型文件已加入 Bundle")
            return
        }

        let outputDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audition")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sampleText = "林峰抬起头，看向远方的天际，心中涌起一阵难以言说的情绪。她轻声说道，我等你很久了。"

        for speakerId in 0..<103 {
            let voice = VoiceConfig(id: "\(speakerId)", speakerId: speakerId,
                                    displayName: "Speaker \(speakerId)")
            do {
                let chunk = try await engine.synthesize(text: sampleText,
                                                        voice: voice, style: .normal)
                let wavURL = outputDir.appendingPathComponent(
                    "speaker_\(String(format: "%03d", speakerId)).wav")
                writeWAV(samples: chunk.samples, sampleRate: chunk.sampleRate, to: wavURL)
                print("✅ Speaker \(speakerId) → \(wavURL.lastPathComponent)")
            } catch {
                print("⚠️ Speaker \(speakerId) 合成失败: \(error)")
            }
        }
        print("🎵 试听文件已生成到 Documents/audition/，共 103 个")
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
            // 防止 NaN/Inf 导致 Int 转换崩溃（某些 speakerId 可能返回无效样本）
            let safe = (s.isNaN || s.isInfinite) ? 0.0 : s
            var v = Int16(max(-32768, min(32767, Int(safe * 32767))))
            pcm.append(contentsOf: withUnsafeBytes(of: &v) { Array($0) })
        }
        try? (header + pcm).write(to: url)
    }
}
#endif
