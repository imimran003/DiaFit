import SwiftUI

struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct TinyLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(DiafitType.caption)
            .foregroundStyle(Color.quietInk)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.66), in: Capsule())
            .overlay(Capsule().stroke(Color.rule.opacity(0.46), lineWidth: 0.8))
    }
}
