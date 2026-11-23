import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AssistantViewModel

    var body: some View {
        ConsoleScreen {
            HStack(spacing: 12) {
                Text("JARVIS AI")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.route.usesHFP {
                    Label("Manos libres", systemImage: "headphones")
                        .font(.footnote)
                        .foregroundStyle(Palette.accent)
                }
            }
            VStack(spacing: 8) {
                ActivityIndicator(state: model.state)
                Text(model.state.title)
                    .font(.title3.weight(.semibold))
                if !model.recognitionMode.isEmpty {
                    Text(model.recognitionMode)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            primaryButton
            if let notice = model.notice { NoticeView(notice: notice) }
            Panel {
                message("Transcripción", content: model.transcript, placeholder: "Tu voz aparecerá aquí.")
                Divider()
                message("Respuesta", content: model.response, placeholder: "La respuesta de JARVIS aparecerá aquí.")
            }
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch model.state {
        case .ready:
            Button(action: model.startListening) {
                Label("Comenzar a escuchar", systemImage: "mic")
            }
            .buttonStyle(ConsoleButtonStyle(prominent: true))
        case .listening:
            Button(action: model.finishListening) {
                Label("Terminar de hablar", systemImage: "stop.fill")
            }
            .buttonStyle(ConsoleButtonStyle(prominent: true))
        default:
            Button(action: model.stop) {
                Label(model.state == .speaking ? "Detener respuesta" : "Cancelar", systemImage: "stop.fill")
            }
            .buttonStyle(ConsoleButtonStyle())
        }
    }

    private func message(_ title: String, content: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityAddTraits(.isHeader)
            Text(content.isEmpty ? placeholder : content)
                .foregroundStyle(content.isEmpty ? Palette.muted : Color.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
