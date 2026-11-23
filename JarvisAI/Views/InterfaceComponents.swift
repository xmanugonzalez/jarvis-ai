import SwiftUI
import UIKit

enum Palette {
    static let background = Color(red: 0.027, green: 0.047, blue: 0.078)
    static let surface = Color(red: 0.055, green: 0.086, blue: 0.133)
    static let border = Color(red: 0.14, green: 0.21, blue: 0.31)
    static let accent = Color(red: 0.37, green: 0.80, blue: 1.00)
    static let muted = Color(red: 0.67, green: 0.75, blue: 0.84)
}

struct ConsoleScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Palette.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

struct ConsoleButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundStyle(prominent ? Palette.background : Palette.accent)
            .background(prominent ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(prominent ? Color.clear : Palette.accent.opacity(0.55), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct NoticeView: View {
    let notice: AssistantNotice
    @Environment(\.openURL) private var openURL

    var body: some View {
        Panel {
            Text(notice.message)
                .font(.subheadline)
            if notice.openSettings {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(ConsoleButtonStyle())
            }
        }
    }
}
