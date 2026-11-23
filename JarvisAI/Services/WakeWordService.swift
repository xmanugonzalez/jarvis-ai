import AVFoundation
import SherpaOnnx

// The decoder and its stream are accessed exclusively on the serial worker queue.
private final class WakeDecoder: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.jarvisai.wake", qos: .userInitiated)
    let pending = DispatchSemaphore(value: 3)
    private var spotter: SherpaOnnxKeywordSpotterWrapper?
    private var rate = 0
    private var nextSample: AVAudioFramePosition?
    private var detected = false

    func reset() {
        detected = false
        nextSample = nil
        spotter?.reset()
    }

    func accept(_ samples: [Float], sampleRate: Int, sampleTime: AVAudioFramePosition?, resources: URL) throws -> Bool {
        guard !detected else { return false }
        if spotter == nil || rate != sampleRate {
            spotter = try makeSpotter(resources)
            rate = sampleRate
        }
        guard let spotter else { throw AssistantError.wakeUnavailable }
        if let sampleTime, let nextSample, sampleTime != nextSample {
            // A dropped input buffer must not splice two unrelated fragments.
            spotter.reset()
        }
        nextSample = sampleTime.map { $0 + AVAudioFramePosition(samples.count) }
        spotter.acceptWaveform(samples: samples, sampleRate: sampleRate)
        while spotter.isReady() {
            spotter.decode()
            if spotter.getResult().keyword == "Jarvis" {
                detected = true
                return true
            }
        }
        return false
    }

    private func makeSpotter(_ resources: URL) throws -> SherpaOnnxKeywordSpotterWrapper {
        try autoreleasepool {
            let suffix = "-epoch-12-avg-2-chunk-16-left-64.int8.onnx"
            func file(_ name: String) -> String { resources.appendingPathComponent(name).path }
            let paths = [file("encoder" + suffix), file("decoder" + suffix), file("joiner" + suffix),
                         file("tokens.txt"), file("jarvis.txt")]
            guard paths.allSatisfy({ FileManager.default.isReadableFile(atPath: $0) }) else {
                throw AssistantError.wakeUnavailable
            }
            let transducer = sherpaOnnxOnlineTransducerModelConfig(encoder: paths[0], decoder: paths[1], joiner: paths[2])
            let model = sherpaOnnxOnlineModelConfig(tokens: paths[3], transducer: transducer, numThreads: 1)
            var config = sherpaOnnxKeywordSpotterConfig(featConfig: sherpaOnnxFeatureConfig(), modelConfig: model,
                                                        keywordsFile: paths[4], numTrailingBlanks: 2, keywordsThreshold: 0.35)
            let spotter = SherpaOnnxKeywordSpotterWrapper(config: &config)
            guard spotter.spotter != nil, spotter.stream != nil else { throw AssistantError.wakeUnavailable }
            return spotter
        }
    }
}

// The tap never waits for the UI to change consumers. Switching is synchronized
// with append(_:) so no buffer reaches Speech after endAudio().
private final class CaptureGate {
    private let lock = NSLock()
    private var consumer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    func set(_ consumer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?) {
        lock.lock()
        self.consumer = consumer
        lock.unlock()
    }

    func receive(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        consumer?(buffer, time)
    }
}

@MainActor
final class WakeWordService {
    private let decoder = WakeDecoder()
    private let gate = CaptureGate()
    private var engine: AVAudioEngine?
    private var runID: UUID?
    private var observer: NSObjectProtocol?
    private var cue: AVAudioPlayer?

    var inputFormat: AVAudioFormat? { engine?.inputNode.outputFormat(forBus: 0) }
    var microphoneActive: Bool { engine?.isRunning == true }

    func start(detected: @escaping () -> Void, failed: @escaping (Error) -> Void) throws {
        guard let resources = Bundle.main.url(forResource: "WakeWord", withExtension: nil, subdirectory: "KokoroSupport") else {
            throw AssistantError.wakeUnavailable
        }
        if engine == nil { try startEngine(failed: failed) }
        guard microphoneActive else { throw AssistantError.captureChanged }
        let id = UUID()
        runID = id
        let decoder = self.decoder
        decoder.queue.async { decoder.reset() }
        gate.set { [weak self] buffer, time in
            guard let channel = buffer.floatChannelData?.pointee, buffer.frameLength > 0,
                  decoder.pending.wait(timeout: .now()) == .success else { return }
            let samples = stride(from: 0, to: Int(buffer.frameLength) * buffer.stride, by: buffer.stride).map { channel[$0] }
            let rate = Int(buffer.format.sampleRate)
            let position = time.isSampleTimeValid ? time.sampleTime : nil
            decoder.queue.async { [weak self] in
                defer { decoder.pending.signal() }
                do {
                    if try decoder.accept(samples, sampleRate: rate, sampleTime: position, resources: resources) {
                        DispatchQueue.main.async { [weak self] in
                            guard self?.runID == id else { return }
                            detected()
                        }
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard self?.runID == id else { return }
                        failed(error)
                    }
                }
            }
        }
    }

    private func startEngine(failed: @escaping (Error) -> Void) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw AssistantError.noInput
        }
        self.engine = engine
        let gate = self.gate
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
            gate.receive(buffer, time)
        }
        do {
            try engine.start()
        } catch {
            stop()
            throw error
        }
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.engine === engine, !engine.isRunning else { return }
                failed(AssistantError.captureChanged)
            }
        }
    }

    func discardAudio() {
        runID = nil
        gate.set(nil)
        cue?.stop()
        cue = nil
    }

    func routeToSpeech(_ consumer: @escaping (AVAudioPCMBuffer) -> Void) {
        discardAudio()
        gate.set { buffer, _ in consumer(buffer) }
    }

    func stop() {
        discardAudio()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
    }

    func playCue() throws -> Duration {
        let rate: UInt32 = 16_000
        let frames = 1_920
        let size = UInt32(frames * 2)
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        append(size + 36)
        wave.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(rate)
        append(rate * 2)
        append(UInt16(2))
        append(UInt16(16))
        wave.append(contentsOf: "data".utf8)
        append(size)
        for index in 0..<frames {
            let time = Double(index) / Double(rate)
            let envelope = sin(.pi * Double(index) / Double(frames - 1))
            append(Int16(7_000 * envelope * sin(2 * .pi * 660 * time)))
        }
        let player = try AVAudioPlayer(data: wave)
        guard player.play() else { throw AssistantError.playbackFailed }
        cue = player
        return .seconds(player.duration + 0.18)
    }
}
