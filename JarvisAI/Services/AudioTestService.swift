import AVFoundation

@MainActor
final class AudioTestService: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private let slots: [URL]
    private var savedURL: URL?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var recordCompletion: ((Bool) -> Void)?
    private var playCompletion: ((Bool) -> Void)?

    var hasRecording: Bool { savedURL != nil }

    init(directory: URL) {
        slots = ["jarvis-test-a.m4a", "jarvis-test-b.m4a"].map { directory.appendingPathComponent($0) }
        super.init()
        for slot in slots { try? FileManager.default.removeItem(at: slot) }
    }

    static func authorizeMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func record(completion: @escaping (Bool) -> Void) throws {
        let url = slots[0] == savedURL ? slots[1] : slots[0]
        try? FileManager.default.removeItem(at: url)
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        recorder.delegate = self
        self.recorder = recorder
        recordCompletion = completion
        guard recorder.record(forDuration: 30) else {
            cancel()
            throw AssistantError.recordingFailed
        }
    }

    func finishRecording() {
        guard let recorder else { return }
        recorder.stop()
        completeRecording(ObjectIdentifier(recorder), success: true)
    }

    private func completeRecording(_ identifier: ObjectIdentifier, success: Bool) {
        guard let recorder, ObjectIdentifier(recorder) == identifier else { return }
        let callback = recordCompletion
        self.recorder = nil
        recordCompletion = nil
        let candidate = recorder.url
        let duration = (try? AVAudioPlayer(contentsOf: candidate))?.duration ?? 0
        let saved = success && duration > 0
        if saved {
            if let savedURL { try? FileManager.default.removeItem(at: savedURL) }
            savedURL = candidate
        } else {
            recorder.stop()
            try? FileManager.default.removeItem(at: candidate)
        }
        callback?(saved)
    }

    func play(completion: @escaping (Bool) -> Void) throws {
        guard let savedURL else { throw AssistantError.playbackFailed }
        let player = try AVAudioPlayer(contentsOf: savedURL)
        player.delegate = self
        self.player = player
        playCompletion = completion
        guard player.play() else {
            cancel()
            throw AssistantError.playbackFailed
        }
    }

    func cancel() {
        let pending = recorder
        recorder = nil
        recordCompletion = nil
        pending?.stop()
        if let pending { try? FileManager.default.removeItem(at: pending.url) }
        let playing = player
        player = nil
        playCompletion = nil
        playing?.stop()
    }

    private func completePlayback(_ identifier: ObjectIdentifier, success: Bool) {
        guard let player, ObjectIdentifier(player) == identifier else { return }
        let callback = playCompletion
        self.player = nil
        playCompletion = nil
        callback?(success)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor in self.completeRecording(identifier, success: flag) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor in self.completeRecording(identifier, success: false) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor in self.completePlayback(identifier, success: flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor in self.completePlayback(identifier, success: false) }
    }
}
