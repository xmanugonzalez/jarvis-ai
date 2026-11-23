import AVFoundation
import Combine
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
                    NavigationLink {
                        VoiceSelectionView(model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voz")
                            Text(selectedVoiceTitle)
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(minHeight: 44)
                    }
                    voiceSlider("Tono", value: $model.settings.speechPitch, range: AssistantSettings.pitchRange)
                    voiceSlider("Velocidad", value: $model.settings.speechRate, range: AssistantSettings.rateRange)
                    voiceSlider("Volumen", value: $model.settings.speechVolume, range: AssistantSettings.volumeRange)
                    Button { model.previewVoice() } label: {
                        Label("Probar voz y ajustes", systemImage: "speaker.wave.2")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Voz e idioma")
                } footer: {
                    Text("El modo automático prefiere una voz masculina y, entre las voces de ese tipo, la mayor calidad disponible.")
                }
                .disabled(!model.isIdle)
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
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)
            .receive(on: DispatchQueue.main)) { _ in
            model.refreshVoices()
        }
    }

    private var selectedVoiceTitle: String {
        let id = model.settings.voiceID
        guard !id.isEmpty else { return "Automática" }
        guard let voice = model.voices.first(where: { $0.id == id }) else {
            return "Voz guardada no disponible · se usará la automática"
        }
        return "\(voice.name) · \(SpanishVoice.languageTitle(voice.language)) · \(voice.quality.title)"
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

private struct VoiceSelectionView: View {
    @ObservedObject var model: AssistantViewModel

    var body: some View {
        let byLanguage = Dictionary(grouping: model.voices, by: \.language)
        Form {
            Section {
                selectionButton("Automática", id: "")
                Button { model.previewVoice("") } label: {
                    Label("Escuchar voz automática", systemImage: "speaker.wave.2")
                        .frame(minHeight: 44)
                }
                .disabled(!model.isIdle || model.voices.isEmpty)
            }
            .listRowBackground(Palette.surface)

            ForEach(byLanguage.keys.sorted(), id: \.self) { language in
                let byQuality = Dictionary(grouping: byLanguage[language] ?? [], by: \.quality)
                ForEach(VoiceQuality.allCases, id: \.self) { quality in
                    if let voices = byQuality[quality] {
                        Section {
                            ForEach(voices.sorted {
                                $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
                            }) { voice in
                                VStack(alignment: .leading, spacing: 0) {
                                    selectionButton(voice.male ? "\(voice.name) · masculina" : voice.name, id: voice.id)
                                    Button { model.previewVoice(voice.id) } label: {
                                        Label("Escuchar demostración", systemImage: "speaker.wave.2")
                                            .frame(minHeight: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Escuchar demostración de \(voice.name)")
                                    .disabled(!model.isIdle)
                                }
                            }
                        } header: {
                            Text("\(SpanishVoice.languageTitle(language)) · \(quality.title)")
                        }
                        .listRowBackground(Palette.surface)
                    }
                }
            }

            Section {
                if model.voices.isEmpty {
                    Text("iOS no ofrece voces en español a JARVIS.")
                } else if !model.voices.contains(where: { $0.quality == .premium || $0.quality == .enhanced }) {
                    Text("iOS no ofrece voces Mejoradas o Premium en español a JARVIS.")
                }
                Text("En el iPhone, abre Ajustes → Accesibilidad → Contenido leído → Voces. Selecciona Español y descarga la variante Mejorada o Premium si aparece. Vuelve a JARVIS cuando termine.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            .listRowBackground(Palette.surface)

            if let notice = model.notice {
                Section { NoticeView(notice: notice) }
                    .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Voces en español")
        .onAppear { model.refreshVoices() }
    }

    private func selectionButton(_ title: String, id: String) -> some View {
        let selected = model.settings.voiceID == id
        return Button {
            model.settings.voiceID = id
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(!model.isIdle)
    }
}
