import SwiftUI

struct ActivityIndicator: View {
    let state: AssistantState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animated = !reduceMotion && state != .ready
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let pulse = animated ? (sin(time * 3) + 1) / 2 : 0
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Palette.accent.opacity(0.20 + 0.12 * pulse), .clear],
                        center: .center, startRadius: 12, endRadius: 104
                    ))
                Circle().strokeBorder(Palette.border, lineWidth: 1)
                    .padding(8)
                Circle().strokeBorder(Palette.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .padding(17)
                Circle()
                    .trim(from: 0, to: 0.24)
                    .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(animated ? time.truncatingRemainder(dividingBy: 5) * 72 : -70))
                    .padding(9)
                Circle().strokeBorder(Palette.accent.opacity(0.45), lineWidth: 1)
                    .padding(29)
                Image(systemName: state.symbol)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: 192, height: 192)
        .accessibilityHidden(true)
    }
}
