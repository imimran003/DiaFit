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

struct AtlasRevealModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + (0.06 * progress))
            .blur(radius: (1 - progress) * 10)
            .mask(alignment: .top) {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .scaleEffect(x: 1, y: max(progress, 0.01), anchor: .top)
            }
    }
}

extension AnyTransition {
    static var atlasReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: AtlasRevealModifier(progress: 0),
                identity: AtlasRevealModifier(progress: 1)
            ),
            removal: .modifier(
                active: AtlasRevealModifier(progress: 0),
                identity: AtlasRevealModifier(progress: 1)
            )
        )
    }
}
