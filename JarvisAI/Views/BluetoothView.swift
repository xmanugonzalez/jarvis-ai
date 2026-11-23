import SwiftUI

struct BluetoothView: View {
    @ObservedObject var model: AssistantViewModel

    private var connection: String {
        if model.route.usesHFP { return "Bluetooth manos libres (HFP)" }
        if model.route.usesOtherBluetooth { return "Bluetooth detectado · sin ruta HFP completa" }
        if !model.route.availableHFP.isEmpty { return "Manos libres disponible" }
        return model.route.verified ? "Sin manos libres en la ruta comprobada" : "Sin manos libres detectado"
    }

    var body: some View {
        ConsoleScreen {
            Text("Bluetooth")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Panel {
                Label(connection, systemImage: "headphones")
                    .font(.headline)
                    .foregroundStyle(Palette.accent)
                routeRow("Entrada", model.route.inputs)
                routeRow("Salida", model.route.outputs)
                if !model.route.availableHFP.isEmpty {
                    routeRow("Entradas manos libres disponibles", model.route.availableHFP)
                }
                Text(model.route.verified && model.isIdle ? "Última ruta de la sesión de JARVIS." : "Ruta informada por iOS.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            Button(action: model.checkRoute) {
                Label("Comprobar ruta", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ConsoleButtonStyle())
            .disabled(!model.isIdle)
            Text("Empareja el Y12 Pro en Ajustes → Bluetooth del iPhone y luego comprueba la ruta aquí.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)

            Panel {
                Text("Prueba de audio")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Graba hasta 30 segundos y reproduce la toma para comprobar el micrófono y los altavoces.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Button(action: model.toggleRecording) {
                    Label(model.state == .recording ? "Terminar grabación" : "Grabar prueba",
                          systemImage: model.state == .recording ? "stop.fill" : "mic")
                }
                .buttonStyle(ConsoleButtonStyle(prominent: true))
                .disabled(!model.isIdle && model.state != .recording)
                Button(action: model.playRecording) {
                    Label(model.state == .playing ? "Detener reproducción" : "Reproducir grabación",
                          systemImage: model.state == .playing ? "stop.fill" : "play.fill")
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(!model.hasRecording || (!model.isIdle && model.state != .playing))
            }
            if !model.isIdle {
                Text(model.state.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.accent)
            }
            if let notice = model.notice { NoticeView(notice: notice) }
        }
    }

    private func routeRow(_ title: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.muted)
            Text(names.isEmpty ? "Sin datos" : names.joined(separator: ", "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
