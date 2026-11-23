import SwiftUI

struct RootView: View {
    @ObservedObject var model: AssistantViewModel

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem { Label("Inicio", systemImage: "waveform") }
            BluetoothView(model: model)
                .tabItem { Label("Bluetooth", systemImage: "headphones") }
            SettingsView(model: model)
                .tabItem { Label("Configuración", systemImage: "gearshape") }
        }
    }
}
