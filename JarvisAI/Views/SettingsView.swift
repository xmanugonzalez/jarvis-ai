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
                    Picker("Voz", selection: $model.settings.voiceID) {
                        Text("Automática").tag("")
                        if !model.settings.voiceID.isEmpty,
                           !model.voices.contains(where: { $0.id == model.settings.voiceID }) {
                            Text("Voz guardada no disponible").tag(model.settings.voiceID)
                        }
                        ForEach(model.voices) { voice in
                            Text(voice.title).tag(voice.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Velocidad de habla")
                        Slider(value: $model.settings.speechRate, in: 0.35...0.60, step: 0.01) {
                            Text("Velocidad de habla")
                        } minimumValueLabel: {
                            Text("Lenta").font(.caption)
                        } maximumValueLabel: {
                            Text("Rápida").font(.caption)
                        }
                        .frame(minHeight: 44)
                    }
                    Button(action: model.previewVoice) {
                        Label("Probar voz", systemImage: "speaker.wave.2")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Voz e idioma")
                } footer: {
                    Text("La voz automática prefiere las voces masculinas que iOS ofrece en español.")
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
    }
}
