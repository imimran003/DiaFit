import SwiftUI
import UIKit

/// The same visual travels from thread to atlas to detail. Member photos remain
/// full-bleed and recognisable; generated/bundled editorial art keeps the
/// art-directed stage treatment used by the rest of the product.
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
            if isOriginalPhoto, let image = storedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            } else {
                TimelineView(.animation(minimumInterval: usesStaticRendering ? 3_600 : 1 / 60)) { timeline in
                    FoodStage(artwork: meal.artwork)
                        .overlay {
                            if let image = storedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(imageScale)
                                    .padding(imagePadding)
                            } else if meal.artwork == .neutral {
                                DeterministicMealComposition(
                                    items: meal.analysis?.detectedItems ?? [],
                                    fallbackTitle: meal.title,
                                    isCompact: treatment == .atlas
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
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var storedImage: UIImage? {
        guard let fileName = meal.visualIdentity?.assetFileName,
              let url = MealVisualAssetStore.liveURL(for: fileName) else { return nil }
        return FoodImageCache.image(at: url, cacheKey: "meal-visual-\(fileName)")
    }

    private var isOriginalPhoto: Bool {
        meal.visualIdentity?.source == .originalPhoto
    }

    private var accessibilityDescription: String {
        switch meal.visualIdentity?.source {
        case .originalPhoto: return "Your meal photo of \(meal.title)"
        case .generatedEditorial: return "Generated food image of \(meal.title)"
        case .bundledEditorial: return "Studio food image of \(meal.title)"
        case .deterministicPlaceholder, .none: return "Meal visual for \(meal.title)"
        }
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
    let isCompact: Bool

    var body: some View {
        Group {
            if items.isEmpty {
                genericFallback
            } else {
                componentComposition
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? 10 : 16)
    }

    private var componentComposition: some View {
        VStack(spacing: isCompact ? 7 : 11) {
            HStack(spacing: 10) {
                ForEach(items.prefix(isCompact ? 2 : 3)) { item in
                    componentTile(item)
                }
                if isCompact, items.count > 2 {
                    Text("+\(items.count - 2)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                }
            }
            Text(isCompact
                 ? fallbackTitle.uppercased()
                 : items.map { "\($0.quantity.formatted(.number.precision(.fractionLength(0...1)))) \($0.displayName)" }.joined(separator: " · ").uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(isCompact ? 1 : 2)
        }
    }

    @ViewBuilder
    private func componentTile(_ item: DetectedFoodItem) -> some View {
        let descriptor = FoodGlyphResolver().descriptor(
            canonicalFoodID: item.canonicalFoodId,
            category: item.category
        )
        VStack(spacing: 5) {
            FoodGlyphView(kind: descriptor.kind, quantity: item.quantity)
                .frame(width: 54, height: 54)
                .background(
                    FoodGlyphPalette.tint(for: descriptor.kind).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.11), lineWidth: 0.75)
                }
            Text(item.displayName.uppercased())
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
        }
        .frame(maxWidth: 74)
    }

    private var genericFallback: some View {
        let descriptor = FoodGlyphResolver().descriptor(
            canonicalFoodID: fallbackTitle,
            category: .unknown
        )
        return VStack(spacing: 8) {
            FoodGlyphView(kind: descriptor.kind, quantity: 1)
                .frame(width: 58, height: 58)
                .background(
                    FoodGlyphPalette.tint(for: descriptor.kind).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
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

/// Native, deterministic food illustrations for the offline visual system.
/// They remain crisp at every Dynamic Type and display scale, require no
/// network service, and avoid the inconsistent platform rendering of emoji.
private struct FoodGlyphView: View {
    let kind: FoodGlyphKind
    let quantity: Double

    @ViewBuilder
    var body: some View {
        switch kind {
        case .water:
            Image(systemName: "drop.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
        case .coffee:
            CupGlyph(
                cup: Color(red: 0.95, green: 0.88, blue: 0.76),
                drink: Color(red: 0.34, green: 0.20, blue: 0.13)
            )
        case .tea:
            CupGlyph(
                cup: Color(red: 0.91, green: 0.89, blue: 0.72),
                drink: Color(red: 0.55, green: 0.38, blue: 0.14)
            )
        case .flatbread:
            FlatbreadGlyph()
        case .rice:
            BowlGlyph(style: .rice)
        case .lentils:
            BowlGlyph(style: .lentils)
        case .curry:
            BowlGlyph(style: .curry)
        case .egg:
            EggGlyph(quantity: quantity)
        case .sprouts:
            SproutsGlyph()
        case .fruit:
            FruitGlyph()
        case .vegetables:
            Image(systemName: "carrot.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
                .rotationEffect(.degrees(-18))
        case .dairy:
            DairyGlyph()
        case .shake:
            Image(systemName: "waterbottle.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
        case .beverage:
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
        case .fish:
            Image(systemName: "fish.fill")
                .font(.system(size: 31, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
        case .meat:
            ProteinGlyph()
        case .snack:
            SnackGlyph()
        case .dessert:
            Image(systemName: "birthday.cake.fill")
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(FoodGlyphPalette.tint(for: kind))
        case .meal:
            Image(systemName: "fork.knife")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

private enum FoodGlyphPalette {
    static func tint(for kind: FoodGlyphKind) -> Color {
        switch kind {
        case .water: return Color(red: 0.50, green: 0.78, blue: 0.91)
        case .coffee: return Color(red: 0.75, green: 0.52, blue: 0.32)
        case .tea: return Color(red: 0.70, green: 0.75, blue: 0.40)
        case .flatbread: return Color(red: 0.92, green: 0.72, blue: 0.39)
        case .rice: return Color(red: 0.96, green: 0.91, blue: 0.75)
        case .lentils: return Color(red: 0.93, green: 0.66, blue: 0.24)
        case .curry: return Color(red: 0.93, green: 0.53, blue: 0.22)
        case .egg: return Color(red: 0.98, green: 0.82, blue: 0.35)
        case .sprouts: return Color(red: 0.62, green: 0.86, blue: 0.40)
        case .fruit: return Color(red: 0.89, green: 0.38, blue: 0.35)
        case .vegetables: return Color(red: 0.54, green: 0.82, blue: 0.34)
        case .dairy: return Color(red: 0.84, green: 0.89, blue: 0.92)
        case .shake: return Color(red: 0.86, green: 0.73, blue: 0.48)
        case .beverage: return Color(red: 0.67, green: 0.80, blue: 0.76)
        case .fish: return Color(red: 0.52, green: 0.77, blue: 0.79)
        case .meat: return Color(red: 0.83, green: 0.47, blue: 0.38)
        case .snack: return Color(red: 0.88, green: 0.71, blue: 0.40)
        case .dessert: return Color(red: 0.88, green: 0.61, blue: 0.73)
        case .meal: return .white
        }
    }
}

private struct CupGlyph: View {
    let cup: Color
    let drink: Color

    var body: some View {
        ZStack {
            Capsule()
                .stroke(cup.opacity(0.86), lineWidth: 3)
                .frame(width: 13, height: 14)
                .offset(x: 17, y: 4)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(cup)
                .frame(width: 31, height: 24)
                .offset(x: -2, y: 5)
            Ellipse()
                .fill(drink)
                .frame(width: 26, height: 8)
                .offset(x: -2, y: -5)
            Capsule()
                .fill(cup.opacity(0.85))
                .frame(width: 39, height: 3)
                .offset(y: 19)
            ForEach(0..<2, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.65))
                    .frame(width: 2, height: 11)
                    .offset(x: CGFloat(index * 9 - 5), y: -19)
                    .rotationEffect(.degrees(index == 0 ? -8 : 8))
            }
        }
    }
}

private struct FlatbreadGlyph: View {
    private let spotOffsets: [CGSize] = [
        .init(width: -9, height: -7),
        .init(width: 7, height: -9),
        .init(width: 11, height: 6),
        .init(width: -5, height: 10),
        .init(width: 0, height: 0)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.69, green: 0.45, blue: 0.22))
                .frame(width: 35, height: 35)
                .offset(x: 5, y: 4)
            Circle()
                .fill(Color(red: 0.94, green: 0.73, blue: 0.39))
                .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 1))
                .frame(width: 38, height: 38)
                .offset(x: -4, y: -3)
            ForEach(Array(spotOffsets.enumerated()), id: \.offset) { index, offset in
                Circle()
                    .fill(Color(red: 0.58, green: 0.34, blue: 0.16).opacity(index == 4 ? 0.48 : 0.68))
                    .frame(width: index == 4 ? 4 : 3, height: index == 4 ? 4 : 3)
                    .offset(x: offset.width - 4, y: offset.height - 3)
            }
        }
    }
}

private struct BowlGlyph: View {
    enum Style { case rice, lentils, curry }
    let style: Style

    var body: some View {
        ZStack {
            Ellipse()
                .fill(foodColor)
                .frame(width: 39, height: 17)
                .offset(y: -2)
            if style == .rice {
                ForEach(0..<9, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index.isMultiple(of: 3) ? 0.78 : 0.98))
                        .frame(width: 7, height: 2.2)
                        .rotationEffect(.degrees(Double(index * 31)))
                        .offset(
                            x: CGFloat((index % 3) * 10 - 10),
                            y: CGFloat((index / 3) * 4 - 6)
                        )
                }
            } else {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? .white.opacity(0.52) : garnishColor)
                        .frame(width: 3.5, height: 3.5)
                        .offset(
                            x: CGFloat((index % 4) * 8 - 12),
                            y: CGFloat((index / 4) * 7 - 5)
                        )
                }
            }
            BowlShape()
                .fill(Color(red: 0.92, green: 0.91, blue: 0.82))
                .overlay(BowlShape().stroke(.white.opacity(0.45), lineWidth: 1))
                .frame(width: 42, height: 23)
                .offset(y: 10)
        }
    }

    private var foodColor: Color {
        switch style {
        case .rice: return Color(red: 0.98, green: 0.94, blue: 0.80)
        case .lentils: return Color(red: 0.91, green: 0.62, blue: 0.18)
        case .curry: return Color(red: 0.91, green: 0.44, blue: 0.16)
        }
    }

    private var garnishColor: Color {
        style == .curry
            ? Color(red: 0.51, green: 0.72, blue: 0.26)
            : Color(red: 0.78, green: 0.38, blue: 0.14)
    }
}

private struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.width, y: 0),
            control1: CGPoint(x: rect.width * 0.20, y: rect.height),
            control2: CGPoint(x: rect.width * 0.80, y: rect.height)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.05))
        path.addCurve(
            to: CGPoint(x: 0, y: rect.height * 0.05),
            control1: CGPoint(x: rect.width * 0.76, y: rect.height * 1.04),
            control2: CGPoint(x: rect.width * 0.24, y: rect.height * 1.04)
        )
        path.closeSubpath()
        return path
    }
}

private struct EggGlyph: View {
    let quantity: Double

    var body: some View {
        HStack(spacing: -8) {
            ForEach(0..<min(3, max(1, Int(quantity.rounded()))), id: \.self) { _ in
                Ellipse()
                    .fill(Color(red: 1, green: 0.95, blue: 0.82))
                    .overlay {
                        Circle()
                            .fill(FoodGlyphPalette.tint(for: .egg))
                            .frame(width: 11, height: 11)
                    }
                    .overlay(Ellipse().stroke(.white.opacity(0.62), lineWidth: 1))
                    .frame(width: 23, height: 30)
            }
        }
    }
}

private struct SproutsGlyph: View {
    var body: some View {
        ZStack {
            BowlShape()
                .fill(Color.white.opacity(0.9))
                .frame(width: 38, height: 20)
                .offset(y: 14)
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        index.isMultiple(of: 2)
                            ? FoodGlyphPalette.tint(for: .sprouts)
                            : Color(red: 0.44, green: 0.73, blue: 0.35)
                    )
                    .rotationEffect(.degrees(Double(index * 29 - 58)))
                    .offset(x: CGFloat(index * 7 - 14), y: CGFloat(abs(index - 2) * 3 - 6))
            }
        }
    }
}

private struct FruitGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.96, green: 0.60, blue: 0.20))
                .frame(width: 29, height: 29)
                .offset(x: 7, y: 5)
            Circle()
                .fill(FoodGlyphPalette.tint(for: .fruit))
                .frame(width: 31, height: 31)
                .offset(x: -7, y: 2)
            Image(systemName: "leaf.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.58, green: 0.82, blue: 0.35))
                .rotationEffect(.degrees(-35))
                .offset(x: 5, y: -17)
        }
    }
}

private struct DairyGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FoodGlyphPalette.tint(for: .dairy))
                .frame(width: 35, height: 29)
                .offset(y: 5)
            Ellipse()
                .fill(.white.opacity(0.98))
                .frame(width: 32, height: 10)
                .offset(y: -8)
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.50, green: 0.68, blue: 0.76))
                .offset(y: 5)
        }
    }
}

private struct ProteinGlyph: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(FoodGlyphPalette.tint(for: .meat))
                .frame(width: 38, height: 26)
                .rotationEffect(.degrees(-14))
            Capsule()
                .fill(Color(red: 0.98, green: 0.82, blue: 0.69))
                .frame(width: 16, height: 6)
                .rotationEffect(.degrees(-14))
            Circle()
                .fill(Color(red: 0.96, green: 0.90, blue: 0.77))
                .frame(width: 8, height: 8)
                .offset(x: 15, y: -6)
        }
    }
}

private struct SnackGlyph: View {
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2)
                          ? FoodGlyphPalette.tint(for: .snack)
                          : Color(red: 0.72, green: 0.48, blue: 0.25))
                    .overlay(Circle().stroke(.white.opacity(0.32), lineWidth: 0.7))
                    .frame(width: 16, height: 16)
                    .offset(
                        x: CGFloat((index % 3) * 14 - 14),
                        y: CGFloat((index / 3) * 15 - 7)
                    )
            }
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
