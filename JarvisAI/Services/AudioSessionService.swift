import AVFoundation

@MainActor
final class AudioSessionService {
    enum Event {
        case routeChanged(AVAudioSession.RouteChangeReason), interrupted, interruptionEnded, mediaReset
    }

    var onEvent: ((Event) -> Void)?
    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []
    private(set) var active = false

    init() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { [weak self] notification in
                let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
                let reason = AVAudioSession.RouteChangeReason(rawValue: rawValue) ?? .unknown
                Task { @MainActor in
                    self?.onEvent?(.routeChanged(reason))
                }
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { [weak self] notification in
                guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: rawValue) else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if type == .began {
                        self.active = false
                    }
                    self.onEvent?(type == .began ? .interrupted : .interruptionEnded)
                }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.active = false
                    self.onEvent?(.mediaReset)
                }
            }
        ]
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func activate(settings: AssistantSettings) async throws -> AudioRoute {
        try session.setCategory(.playAndRecord, mode: .default, options: .allowBluetooth)
        try session.setActive(true)
        active = true

        let inputs = session.availableInputs ?? []
        let currentHFP = session.currentRoute.inputs.first { $0.portType == .bluetoothHFP }
        let preferred = settings.preferBluetooth
            ? (inputs.first { $0.uid == currentHFP?.uid } ?? inputs.first { $0.portType == .bluetoothHFP })
            : nil
        if session.preferredInput?.uid != preferred?.uid {
            try session.setPreferredInput(preferred)
        }

        if let preferred {
            // AVAudioSession confirms the requested route asynchronously.
            for _ in 0..<20 {
                try Task.checkCancellation()
                let route = session.currentRoute
                if route.inputs.contains(where: { $0.uid == preferred.uid }),
                   route.outputs.contains(where: { $0.portType == .bluetoothHFP }) {
                    return snapshot()
                }
                try await Task.sleep(for: .milliseconds(75))
            }
            throw AssistantError.routeUnavailable
        }

        let route = session.currentRoute
        if settings.usePhoneSpeaker,
           !route.inputs.isEmpty,
           route.inputs.allSatisfy({ $0.portType == .builtInMic }),
           route.outputs.map(\.portType) == [.builtInReceiver] {
            try session.overrideOutputAudioPort(.speaker)
            for _ in 0..<10 {
                try Task.checkCancellation()
                if session.currentRoute.outputs.map(\.portType) != [.builtInReceiver] { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        return snapshot()
    }

    func deactivate() {
        guard active else { return }
        try? session.overrideOutputAudioPort(.none)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        active = false
    }

    func snapshot() -> AudioRoute {
        let route = session.currentRoute
        let ports = route.inputs + route.outputs
        return AudioRoute(
            inputs: route.inputs.map(\.portName),
            outputs: route.outputs.map(\.portName),
            availableHFP: (session.availableInputs ?? []).filter { $0.portType == .bluetoothHFP }.map(\.portName),
            usesHFP: route.inputs.contains { $0.portType == .bluetoothHFP }
                && route.outputs.contains { $0.portType == .bluetoothHFP },
            usesOtherBluetooth: ports.contains {
                [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0.portType)
            },
            verified: active,
            signature: route.inputs.map { "in:\($0.uid)" } + route.outputs.map { "out:\($0.uid)" }
        )
    }
}
