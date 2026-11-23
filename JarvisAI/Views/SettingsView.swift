import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AssistantViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Idioma", selection: $model.settings.language) {
                        ForEach(SpanishLocale.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    voiceSlider("Velocidad", value: $model.settings.speechRate, range: AssistantSettings.rateRange)
                    voiceSlider("Volumen", value: $model.settings.speechVolume, range: AssistantSettings.volumeRange)
                } header: {
                    Text("Voz e idioma")
                }
                .disabled(!model.isIdle)
                .listRowBackground(Palette.surface)

                KokoroSettingsSection(model: model, store: model.kokoroModel)

                Section {
                    timingSlider("Silencio al terminar", value: $model.settings.silenceSeconds, range: AssistantSettings.silenceRange, step: 0.25)
                    timingSlider("Ventana de conversación", value: $model.settings.conversationSeconds, range: AssistantSettings.conversationRange, step: 1)
                } header: {
                    Text("Modo JARVIS")
                } footer: {
                    Text("Continúa con «y» o «también». Con 0 s de ventana, di «Jarvis» antes de cada pregunta. Durante la ventana, Apple Speech puede captar a quien hable cerca.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    Toggle("Preferir manos libres", isOn: $model.settings.preferBluetooth)
                    Toggle("Altavoz si se usa el iPhone", isOn: $model.settings.usePhoneSpeaker)
                    Toggle("Solo sin conexión", isOn: $model.settings.offlineOnly)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Solo sin conexión exige reconocimiento local para el idioma elegido. Si lo desactivas, iOS puede usar el servicio de Apple.")
                }
                .disabled(!model.isIdle)
                .listRowBackground(Palette.surface)

                if let notice = model.notice {
                    Section { NoticeView(notice: notice) }
                        .listRowBackground(Palette.surface)
                }

                if let diagnostic = model.recognitionDiagnostic {
                    Section {
                        DisclosureGroup("Diagnóstico de reconocimiento") {
                            Text(diagnostic)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Configuración")
        }
    }

    private func timingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        let seconds = value.wrappedValue.formatted(.number.precision(.fractionLength(0...2)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(seconds) s").monospacedDigit().foregroundStyle(Palette.muted)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue("\(seconds) segundos")
                .frame(minHeight: 44)
        }
    }

    private func voiceSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let percent = value.wrappedValue.formatted(.percent.precision(.fractionLength(0)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(percent).monospacedDigit().foregroundStyle(Palette.muted)
            }
            .accessibilityHidden(true)
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(title)
                .accessibilityValue(percent)
                .frame(minHeight: 44)
        }
    }
}

private struct KokoroSettingsSection: View {
    @ObservedObject var model: AssistantViewModel
    @ObservedObject var store: KokoroModelStore

    var body: some View {
        Section {
            switch store.status {
            case .ready:
                Label("Modelo descargado", systemImage: "checkmark.circle")
            case .downloading:
                ProgressView("Descargando Kokoro")
                Button("Cancelar descarga", action: store.cancelDownload)
            case .missing, .failed:
                if case .failed(let message) = store.status {
                    Text(message).font(.footnote).foregroundStyle(Palette.muted)
                }
                if store.installedFolder == nil {
                    Button("Descargar Kokoro (142 MB)", action: store.download)
                        .disabled(!model.isIdle)
                }
            }
            if store.installedFolder != nil {
                Button(action: model.previewKokoro) {
                    Label("Escuchar demostración de Kokoro", systemImage: "speaker.wave.2")
                        .frame(minHeight: 44)
                }
                .disabled(!model.isIdle)
                Button("Eliminar archivos de Kokoro", role: .destructive, action: model.removeKokoroModel)
                    .disabled(!model.isIdle)
            }
        } header: {
            Text("Kokoro · español")
        } footer: {
            Text("La voz em_alex se genera en el iPhone. La primera carga puede tardar. Las respuestas se reproducen con Kokoro.")
        }
        .listRowBackground(Palette.surface)
        .onChange(of: store.status) { _, status in
            if status == .ready { model.prepareKokoro() }
        }
    }
}
