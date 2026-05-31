import AVFoundation

final class AudioPipeline {

    private let engine      = AVAudioEngine()
    private let playerNode  = AVAudioPlayerNode()
    private let pitchEffect = AVAudioUnitTimePitch()
    private var isSetup     = false

    var onSentenceComplete: ((SentenceUnit) -> Void)?

    func setup() throws {
        if isSetup { return }
        engine.attach(playerNode)
        engine.attach(pitchEffect)
        engine.connect(playerNode, to: pitchEffect,            format: nil)
        engine.connect(pitchEffect, to: engine.mainMixerNode,  format: nil)
        try engine.start()
        isSetup = true
    }

    func enqueue(chunk: AudioChunk, sentence: SentenceUnit, style: SpeakingStyle) {
        // setup 如果还没运行（例如 stop 后首次 enqueue）
        if !isSetup { try? setup() }
        guard let buffer = makeBuffer(from: chunk) else { return }
        applyStyle(style)
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.onSentenceComplete?(sentence) }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    func pause() {
        playerNode.pause()
    }

    func resume() throws {
        if !engine.isRunning { try engine.start() }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        engine.reset()
        isSetup = false
    }

    private func makeBuffer(from chunk: AudioChunk) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(chunk.samples.count)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(chunk.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        chunk.samples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData?[0].initialize(
                from: ptr.baseAddress!, count: chunk.samples.count)
        }
        return buffer
    }

    private func applyStyle(_ style: SpeakingStyle) {
        pitchEffect.pitch  = style.pitchOffset * 100   // AVAudioUnitTimePitch 单位是 cent
        pitchEffect.rate   = style.rateMultiplier
        engine.mainMixerNode.outputVolume = style.volumeMultiplier
    }
}
