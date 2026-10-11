import SwiftUI

struct MealMomentView: View {
    let meal: Meal
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID
    var associatedGlucoseReadings: [GlucoseReading] = []
    let edit: (Meal) -> Void
    let delete: (Meal) -> Void
    @State private var revealsDetails = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    revealsDetails.toggle()
                }
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 14) {
                            thumbnail
                            mealSummary
                        }
                    } else {
                        HStack(alignment: .center, spacing: 16) {
                            thumbnail
                            mealSummary
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.99))
            .accessibilityHint(revealsDetails ? "Double tap to hide meal details" : "Double tap to reveal meal details")
            .accessibilityIdentifier("Saved meal \(meal.title)")
            .accessibilityLabel("\(meal.mealType), saved meal \(meal.title), \(meal.carbs) grams carbohydrates, \(meal.energy) kcal")

            if revealsDetails {
                VStack(alignment: .leading, spacing: 12) {
                    FoodArtwork(meal: meal, treatment: .detail)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(meal.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.quietInk)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { detailMetrics }
                        VStack(alignment: .leading, spacing: 12) { detailMetrics }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.homeAccentWash.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity)
            }

            if !associatedGlucoseReadings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glucose after this meal")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.quietInk)
                    ForEach(associatedGlucoseReadings) { reading in
                        HStack {
                            Text(reading.type.displayName)
                            Spacer()
                            Text("\(reading.formattedValue) \(reading.unit.shortName)")
                                .fontWeight(.semibold)
                            Text(reading.measuredAt.formatted(.dateTime.hour().minute()))
                                .foregroundStyle(Color.quietInk)
                        }
                        .font(.caption)
                    }
                }
            }
            Rectangle().fill(Color.rule.opacity(0.5)).frame(height: 0.5)
                .padding(.top, 4)
        }
        .foregroundStyle(Color.ink)
        .overlay(alignment: .topTrailing) {
            mealMenu.offset(y: -10)
        }
        .contextMenu {
            if meal.analysis != nil {
                Button("Refine estimate", systemImage: "slider.horizontal.3") { edit(meal) }
            }
            Button("Open meal atlas", systemImage: "square.grid.2x2") { isAtlasOpen = true }
            Button("Delete meal", systemImage: "trash", role: .destructive) { delete(meal) }
        }
    }

    private var thumbnail: some View {
        FoodArtwork(meal: meal, treatment: .thread)
            .matchedGeometryEffect(id: "art-\(meal.id)", in: mealNamespace)
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var mealSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(meal.mealType.uppercased()) · \(meal.time.formatted(date: .omitted, time: .shortened))")
                .font(.caption2.weight(.medium))
                .tracking(0.5)
                .foregroundStyle(Color.quietInk)
                .padding(.trailing, 30)
            Text(meal.title)
                .font(.system(.headline, weight: .medium))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { mainNutrients }
                VStack(alignment: .leading, spacing: 4) { mainNutrients }
            }
            HStack(spacing: 5) {
                Text(meal.subtitle.components(separatedBy: " · ").first ?? meal.subtitle)
                    .lineLimit(1)
                Image(systemName: revealsDetails ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .font(.caption2)
            .foregroundStyle(Color.quietInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mainNutrients: some View {
        Group {
            Text("\(meal.carbs)g carbs").foregroundStyle(Color.homeAccent)
            Text("\(meal.energy) kcal").foregroundStyle(Color.quietInk)
        }
        .font(.subheadline)
        .fixedSize()
    }

    private var detailMetrics: some View {
        Group {
            DetailMetric(label: "Protein", value: "\(meal.protein)g")
            DetailMetric(label: "Fat", value: "\(meal.fat)g")
            DetailMetric(label: "Source", value: meal.confidence.rawValue)
        }
    }

    private var mealMenu: some View {
        Menu {
            if meal.analysis != nil {
                Button("Refine estimate", systemImage: "slider.horizontal.3") { edit(meal) }
            }
            Button("Delete meal", systemImage: "trash", role: .destructive) { delete(meal) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(Color.quietInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Meal actions")
    }
}

private struct DetailMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Color.quietInk)
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(Color.ink)
        }
    }
}
