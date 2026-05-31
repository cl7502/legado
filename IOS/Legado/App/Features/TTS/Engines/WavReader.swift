import Foundation

/// 读取 WAV 文件（PCM 16-bit，小端序）并返回 Float 样本和采样率。
enum WavReader {
    static func load(path: String) -> (samples: [Float], sampleRate: Int)? {
        guard let data = FileManager.default.contents(atPath: path),
              data.count > 44 else { return nil }
        let sampleRate = data.withUnsafeBytes { ptr in
            Int(ptr.load(fromByteOffset: 24, as: UInt32.self).littleEndian)
        }
        let bitsPerSample = data.withUnsafeBytes { ptr in
            Int(ptr.load(fromByteOffset: 34, as: UInt16.self).littleEndian)
        }
        guard bitsPerSample == 16 else { return nil }
        let pcm = data[44...]
        let sampleCount = pcm.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        pcm.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in 0..<min(sampleCount, int16Ptr.count) {
                samples[i] = Float(int16Ptr[i].littleEndian) / 32767.0
            }
        }
        return (samples, sampleRate)
    }
}
