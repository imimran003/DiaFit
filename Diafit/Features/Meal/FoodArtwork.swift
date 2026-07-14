import SwiftUI

/// A compositional food-art placeholder. Remote generated images drop in here by
/// preserving the external frame, clipping, and `matchedGeometryEffect` identity.
struct FoodArtwork: View {
    enum Treatment { case thread, atlas, detail }

    let meal: Meal
    let treatment: Treatment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 30)) { timeline in
                FoodStillLife(artwork: meal.artwork, phase: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .drawingGroup()
                    .layerEffect(
                        ShaderLibrary.lensPass(
                            .float2(proxy.size),
                            .float(reduceMotion ? 0 : Float(timeline.date.timeIntervalSinceReferenceDate))
                        ),
                        maxSampleOffset: CGSize(width: 2, height: 2)
                    )
            }
        }
        .background(stageColor)
        .accessibilityLabel("Studio illustration of \(meal.title)")
    }

    private var stageColor: Color {
        switch meal.artwork {
        case .bowl: .init(red: 0.84, green: 0.77, blue: 0.64)
        case .toast: .init(red: 0.87, green: 0.78, blue: 0.61)
        case .berry: .init(red: 0.65, green: 0.69, blue: 0.84)
        case .pasta: .init(red: 0.82, green: 0.39, blue: 0.25)
        case .green: .init(red: 0.57, green: 0.67, blue: 0.46)
        }
    }
}

private struct FoodStillLife: View {
    let artwork: Meal.Artwork
    let phase: TimeInterval

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.16))
                    .frame(width: size.width * 0.73, height: size.height * 0.19)
                    .blur(radius: 13)
                    .offset(y: size.height * 0.31)

                switch artwork {
                case .bowl: BowlScene(size: size, phase: phase)
                case .toast: ToastScene(size: size, phase: phase)
                case .berry: BerryScene(size: size, phase: phase)
                case .pasta: PastaScene(size: size, phase: phase)
                case .green: SalmonScene(size: size, phase: phase)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

private struct BowlScene: View {
    let size: CGSize
    let phase: TimeInterval
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.93, green: 0.89, blue: 0.79)).frame(width: size.width * 0.72)
            Circle().stroke(.white.opacity(0.57), lineWidth: 5).frame(width: size.width * 0.68)
            ForEach(0..<18, id: \.self) { index in
                Circle()
                    .fill([Color.coral, .lime.opacity(0.9), .saffron, .white.opacity(0.82)][index % 4])
                    .frame(width: size.width * (index % 3 == 0 ? 0.11 : 0.075))
                    .offset(
                        x: cos(Double(index) * 1.71) * size.width * 0.22,
                        y: sin(Double(index) * 1.37) * size.width * 0.19
                    )
            }
            Circle().stroke(Color.ink.opacity(0.38), lineWidth: 3).frame(width: size.width * 0.66)
        }
        .rotationEffect(.degrees(-8))
    }
}

private struct ToastScene: View {
    let size: CGSize
    let phase: TimeInterval
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.12, style: .continuous)
                .fill(Color(red: 0.48, green: 0.23, blue: 0.12))
                .frame(width: size.width * 0.6, height: size.height * 0.58)
                .rotationEffect(.degrees(-10))
            RoundedRectangle(cornerRadius: size.width * 0.1, style: .continuous)
                .fill(Color(red: 0.84, green: 0.57, blue: 0.26))
                .frame(width: size.width * 0.54, height: size.height * 0.52)
                .rotationEffect(.degrees(-10))
            Circle().fill(Color(red: 0.98, green: 0.91, blue: 0.71)).frame(width: size.width * 0.24)
                .overlay(Circle().fill(Color.saffron).frame(width: size.width * 0.1))
                .offset(x: -size.width * 0.08, y: -size.height * 0.07)
            ForEach(0..<7, id: \.self) { index in
                Capsule().fill(Color(red: 0.82, green: 0.2, blue: 0.15)).frame(width: 6, height: 18)
                    .rotationEffect(.degrees(Double(index) * 45))
                    .offset(x: size.width * 0.15, y: size.height * 0.08)
            }
        }
    }
}

private struct BerryScene: View {
    let size: CGSize
    let phase: TimeInterval
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.9, green: 0.83, blue: 0.7)).frame(width: size.width * 0.73)
            Circle().fill(.white.opacity(0.84)).frame(width: size.width * 0.64)
            ForEach(0..<19, id: \.self) { index in
                Circle()
                    .fill(index % 4 == 0 ? Color(red: 0.65, green: 0.15, blue: 0.35) : Color(red: 0.11, green: 0.24, blue: 0.56))
                    .frame(width: index % 4 == 0 ? size.width * 0.11 : size.width * 0.07)
                    .offset(
                        x: cos(Double(index) * 2.13) * size.width * 0.22,
                        y: sin(Double(index) * 1.49) * size.width * 0.19
                    )
            }
            ForEach(0..<12, id: \.self) { index in
                Circle().fill(Color(red: 0.73, green: 0.61, blue: 0.33)).frame(width: 4, height: 4)
                    .offset(x: cos(Double(index) * 0.53) * size.width * 0.25, y: sin(Double(index) * 0.51) * size.width * 0.2)
            }
        }
        .rotationEffect(.degrees(7))
    }
}

private struct PastaScene: View {
    let size: CGSize
    let phase: TimeInterval
    var body: some View {
        ZStack {
            Circle().fill(Color(red: 0.96, green: 0.84, blue: 0.58)).frame(width: size.width * 0.72)
            Circle().fill(Color(red: 0.98, green: 0.67, blue: 0.28)).frame(width: size.width * 0.61)
            ForEach(0..<14, id: \.self) { index in
                Capsule().fill(Color(red: 0.99, green: 0.84, blue: 0.48))
                    .frame(width: size.width * 0.34, height: 9)
                    .rotationEffect(.degrees(Double(index) * 27))
                    .offset(x: cos(Double(index) * 1.3) * size.width * 0.09, y: sin(Double(index) * 1.9) * size.height * 0.09)
            }
            ForEach(0..<5, id: \.self) { index in
                Circle().fill(Color(red: 0.86, green: 0.2, blue: 0.12)).frame(width: 13, height: 13)
                    .offset(x: cos(Double(index) * 1.57) * size.width * 0.2, y: sin(Double(index) * 1.51) * size.height * 0.18)
            }
        }
    }
}

private struct SalmonScene: View {
    let size: CGSize
    let phase: TimeInterval
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.17, style: .continuous)
                .fill(Color(red: 0.93, green: 0.89, blue: 0.78)).frame(width: size.width * 0.76, height: size.height * 0.72)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.94, green: 0.44, blue: 0.29)).frame(width: size.width * 0.37, height: size.height * 0.31)
                .rotationEffect(.degrees(-13)).offset(x: -size.width * 0.11, y: -size.height * 0.05)
            ForEach(0..<11, id: \.self) { index in
                Ellipse().fill(Color(red: 0.23, green: 0.43, blue: 0.18))
                    .frame(width: size.width * 0.15, height: size.width * 0.07)
                    .rotationEffect(.degrees(Double(index) * 31))
                    .offset(x: cos(Double(index) * 0.87) * size.width * 0.21, y: sin(Double(index) * 1.8) * size.height * 0.19)
            }
            ForEach(0..<8, id: \.self) { index in
                Circle().fill(Color(red: 0.75, green: 0.6, blue: 0.37)).frame(width: size.width * 0.07)
                    .offset(x: size.width * 0.19 + cos(Double(index)) * size.width * 0.09, y: size.height * 0.1 + sin(Double(index)) * size.height * 0.11)
            }
        }
        .rotationEffect(.degrees(4))
    }
}
