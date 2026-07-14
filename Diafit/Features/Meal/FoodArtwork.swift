import SwiftUI
import UIKit

/// The food image is a cutout, not a rectangular photograph. That lets one
/// art-directed object travel naturally from a generous thread moment into the
/// denser atlas without inventing a new crop for each destination.
struct FoodArtwork: View {
    enum Treatment { case thread, atlas, detail }

    let meal: Meal
    let treatment: Treatment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// XCTest waits for the process to become visually idle before interacting.
    /// Keep the live lens treatment in production, while giving deterministic UI
    /// tests a static first frame rather than a permanently ticking timeline.
    private var usesStaticRendering: Bool {
        reduceMotion || ProcessInfo.processInfo.arguments.contains("UITestMode")
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: usesStaticRendering ? 3_600 : 1 / 60)) { timeline in
                FoodStage(artwork: meal.artwork)
                    .overlay {
                        if meal.artwork == .neutral {
                            NeutralMealPlaceholder(
                                components: meal.analysis?.detectedItems.map(\.displayName) ?? [meal.title]
                            )
                        } else if let image = FoodImageCache.image(named: meal.artwork.rawValue) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(imageScale)
                                .offset(y: imageOffset)
                                .padding(imagePadding)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .compositingGroup()
                    .layerEffect(
                        ShaderLibrary.lensPass(
                            .float2(proxy.size),
                            .float(usesStaticRendering ? 0 : Float(timeline.date.timeIntervalSinceReferenceDate))
                        ),
                        maxSampleOffset: CGSize(width: 2, height: 2)
                    )
            }
        }
        .accessibilityLabel(meal.artwork == .neutral
            ? "Component placeholder for \(meal.title)"
            : "Studio food image of \(meal.title)")
    }

    private var imageScale: CGFloat {
        switch treatment {
        case .thread: 1.18
        case .atlas: 1.1
        case .detail: 1.24
        }
    }

    private var imagePadding: CGFloat {
        switch treatment {
        case .thread: 7
        case .atlas: 13
        case .detail: 2
        }
    }

    private var imageOffset: CGFloat {
        switch meal.artwork {
        case .pasta, .bowl: 7
        case .green: 4
        case .toast: 11
        case .berry: 2
        case .neutral: 0
        }
    }
}

/// Images are copied as loose PNG resources rather than an asset catalog. An
/// explicit bundle lookup keeps those studio cutouts stable in app, previews,
/// and test-host bundles without repeating decode work during animation ticks.
private enum FoodImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

private struct FoodStage: View {
    let artwork: Meal.Artwork

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                stageColor
                PaperFibers()
                Ellipse()
                    .fill(.black.opacity(0.12))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.height * 0.12)
                    .blur(radius: 14)
                    .offset(y: proxy.size.height * 0.3)
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
                    .padding(proxy.size.width * 0.1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
        }
    }

    private var stageColor: Color {
        switch artwork {
        case .bowl: Color(red: 0.68, green: 0.72, blue: 0.58)
        case .toast: Color(red: 0.76, green: 0.58, blue: 0.41)
        case .berry: Color(red: 0.53, green: 0.58, blue: 0.76)
        case .pasta: Color(red: 0.72, green: 0.31, blue: 0.17)
        case .green: Color(red: 0.45, green: 0.56, blue: 0.42)
        case .neutral: Color(red: 0.38, green: 0.40, blue: 0.35)
        }
    }
}

/// A truthful visual bridge for meals without a verified matching editorial
/// image. It is intentionally graphic rather than photographic, so no one can
/// mistake it for the logged food or portion.
private struct NeutralMealPlaceholder: View {
    let components: [String]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(components.prefix(2).joined(separator: " + ").uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.9)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .padding(.horizontal, 18)
            Text("COMPONENT PLACEHOLDER")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}

private struct PaperFibers: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<88 {
                let seed = Double(index * 37 % 97) / 97
                let x = size.width * CGFloat(seed)
                let y = size.height * CGFloat(Double(index * 61 % 101) / 101)
                let length = 9 + CGFloat(index % 7) * 5
                var fiber = Path()
                fiber.move(to: CGPoint(x: x, y: y))
                fiber.addLine(to: CGPoint(x: x + length, y: y + CGFloat((index % 3) - 1)))
                context.stroke(
                    fiber,
                    with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.07 : 0.035)),
                    lineWidth: index.isMultiple(of: 4) ? 0.7 : 0.35
                )
            }
        }
        .allowsHitTesting(false)
        .blendMode(.softLight)
    }
}
