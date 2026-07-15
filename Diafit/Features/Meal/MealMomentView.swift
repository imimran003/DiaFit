import SwiftUI

struct MealMomentView: View {
    let meal: Meal
    @Binding var isAtlasOpen: Bool
    let mealNamespace: Namespace.ID
    var associatedGlucoseReadings: [GlucoseReading] = []
    let edit: (Meal) -> Void
    let delete: (Meal) -> Void
    @State private var revealsDetails = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.8)) {
                revealsDetails.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                FoodArtwork(meal: meal, treatment: .thread)
                    .matchedGeometryEffect(id: "art-\(meal.id)", in: mealNamespace)
                    .frame(height: 238)
                    .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Text(meal.mealType.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.18), in: Capsule())
                            .padding(13)
                    }

                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.title)
                                .font(DiafitType.title)
                                .foregroundStyle(Color.ink)
                            Text(meal.subtitle)
                                .font(DiafitType.caption)
                                .foregroundStyle(Color.quietInk)
                        }
                        Spacer()
                        Text("\(meal.energy)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text("kcal")
                            .font(DiafitType.caption)
                            .foregroundStyle(Color.quietInk)
                    }

                    HStack(spacing: 7) {
                        MacroPill(value: "\(meal.carbs)g", label: "carbs", color: .coral)
                        MacroPill(value: "\(meal.protein)g", label: "protein", color: .ink)
                        Spacer()
                        Text(revealsDetails ? "less" : "details")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.quietInk)
                    }

                    if revealsDetails {
                        Divider().overlay(Color.rule.opacity(0.65))
                        HStack {
                            DetailMetric(label: "Fat", value: "\(meal.fat)g")
                            Spacer()
                            DetailMetric(label: "Source", value: meal.confidence.rawValue)
                            Spacer()
                            DetailMetric(label: "Logged", value: meal.time.formatted(date: .omitted, time: .shortened))
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        if !associatedGlucoseReadings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GLUCOSE AFTER THIS MEAL")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(Color.quietInk)
                                ForEach(associatedGlucoseReadings) { reading in
                                    HStack {
                                        Text(reading.type.displayName)
                                            .font(DiafitType.caption)
                                        Spacer()
                                        Text("\(reading.formattedValue) \(reading.unit.shortName)")
                                            .font(DiafitType.caption.weight(.semibold))
                                        Text(reading.measuredAt.formatted(.dateTime.hour().minute()))
                                            .font(DiafitType.caption)
                                            .foregroundStyle(Color.quietInk)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
            }
        }
        .buttonStyle(PressableStyle(pressedScale: 0.985))
        .contentShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
        .accessibilityHint("Double tap to reveal meal details")
        .accessibilityIdentifier("Saved meal \(meal.title)")
        .accessibilityLabel("Saved meal \(meal.title), \(meal.energy) kcal")
        .contextMenu {
            if meal.analysis != nil {
                Button("Refine estimate", systemImage: "slider.horizontal.3") { edit(meal) }
            }
            Button("Open meal atlas", systemImage: "square.grid.2x2") { isAtlasOpen = true }
            Button("Delete meal", systemImage: "trash", role: .destructive) { delete(meal) }
        }
    }
}

private struct MacroPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        Text("\(value) \(label)")
            .font(DiafitType.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }
}

private struct DetailMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.quietInk)
            Text(value)
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
        }
    }
}
