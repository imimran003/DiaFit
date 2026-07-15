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
                        if let image = generatedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(imageScale)
                                .padding(imagePadding)
                        } else if meal.artwork == .neutral {
                            DeterministicMealComposition(
                                items: meal.analysis?.detectedItems ?? [],
                                fallbackTitle: meal.title
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
            ? "Deterministic meal image for \(meal.title)"
            : "Studio food image of \(meal.title)")
    }

    private var generatedImage: UIImage? {
        guard let fileName = meal.visualIdentity?.assetFileName,
              let url = MealVisualAssetStore.liveURL(for: fileName) else { return nil }
        return FoodImageCache.image(at: url, cacheKey: "generated-\(fileName)")
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

    static func image(at url: URL, cacheKey: String) -> UIImage? {
        if let cached = cache.object(forKey: cacheKey as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: cacheKey as NSString)
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
private struct DeterministicMealComposition: View {
    let items: [DetectedFoodItem]
    let fallbackTitle: String

    var body: some View {
        Group {
            if items.isEmpty {
                genericFallback
            } else {
                componentComposition
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private var componentComposition: some View {
        VStack(spacing: 11) {
            HStack(spacing: 10) {
                ForEach(items.prefix(3)) { item in
                    componentTile(item)
                }
            }
            Text(items.map { "\($0.quantity.formatted(.number.precision(.fractionLength(0...1)))) \($0.displayName)" }.joined(separator: " · ").uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func componentTile(_ item: DetectedFoodItem) -> some View {
        VStack(spacing: 5) {
            icon(for: item)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            Text(item.displayName.uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: 74)
    }

    @ViewBuilder
    private func icon(for item: DetectedFoodItem) -> some View {
        if item.canonicalFoodId.contains("egg") || item.category == .egg {
            HStack(spacing: -8) {
                ForEach(0..<min(3, max(1, Int(item.quantity.rounded()))), id: \.self) { _ in
                    Ellipse()
                        .fill(Color(red: 1, green: 0.92, blue: 0.67))
                        .overlay(Ellipse().stroke(.white.opacity(0.62), lineWidth: 1))
                        .frame(width: 22, height: 29)
                }
            }
        } else {
            switch item.category {
            case .sprouts:
            ZStack {
                Capsule().fill(Color.white.opacity(0.92)).frame(width: 36, height: 18).offset(y: 13)
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(index.isMultiple(of: 2) ? Color.lime : Color(red: 0.55, green: 0.87, blue: 0.46))
                        .rotationEffect(.degrees(Double(index * 29 - 58)))
                        .offset(x: CGFloat(index * 7 - 14), y: CGFloat(abs(index - 2) * 3 - 6))
                }
            }
            case .egg:
                EmptyView()
            case .supplement:
            Image(systemName: "waterbottle.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color(red: 0.88, green: 0.79, blue: 0.52))
            default:
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var genericFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(fallbackTitle.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.9)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            Text("COMPONENT VISUAL")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.62))
        }
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
