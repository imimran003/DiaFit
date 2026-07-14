import SwiftUI
import UIKit

struct MealAtlasView: View {
    let day: Day
    @Binding var isPresented: Bool
    let mealNamespace: Namespace.ID
    @State private var selectedMeal: Meal?
    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: 11),
        GridItem(.flexible(), spacing: 11)
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            VisualEffectBlur(style: .systemUltraThinMaterialLight)
                .ignoresSafeArea()
                .overlay(Color.paper.opacity(0.72).ignoresSafeArea())

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    AtlasHeader(day: day, close: close)

                    Text("A small visual record of your day. Tap a plate for its quiet details.")
                        .font(DiafitType.body)
                        .foregroundStyle(Color.quietInk)
                        .lineSpacing(3)

                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(day.meals) { meal in
                            Button {
                                withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
                                    selectedMeal = meal
                                }
                            } label: {
                                AtlasTile(meal: meal, mealNamespace: mealNamespace)
                            }
                            .buttonStyle(PressableStyle(pressedScale: 0.96))
                            .accessibilityLabel("\(meal.mealType), \(meal.title)")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, selectedMeal == nil ? 36 : 250)
            }
            .offset(y: dragOffset)

            if let selectedMeal {
                MealDetailCurtain(meal: selectedMeal, dismiss: { self.selectedMeal = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .gesture(dismissGesture)
        .onChange(of: isPresented) { _, presented in
            if !presented { selectedMeal = nil }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard selectedMeal == nil, value.translation.height > 0 else { return }
                dragOffset = min(value.translation.height, 150)
            }
            .onEnded { value in
                guard selectedMeal == nil else { return }
                if value.translation.height > 100 || value.predictedEndTranslation.height > 220 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { dragOffset = 0 }
                }
            }
    }

    private func close() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) {
            isPresented = false
            dragOffset = 0
        }
    }
}

private struct AtlasHeader: View {
    let day: Day
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meal atlas")
                    .font(DiafitType.display)
                    .foregroundStyle(Color.ink)
                Text(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.quietInk)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
            }
            .buttonStyle(PressableStyle(pressedScale: 0.88))
            .accessibilityLabel("Close meal atlas")
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color.ink.opacity(0.18))
                .frame(width: 36, height: 4)
                .offset(y: -9)
        }
    }
}

private struct AtlasTile: View {
    let meal: Meal
    let mealNamespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FoodArtwork(meal: meal, treatment: .atlas)
                .matchedGeometryEffect(id: "art-\(meal.id)", in: mealNamespace)
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Text(meal.mealType.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(10)
                        .shadow(color: .black.opacity(0.38), radius: 5)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(meal.carbs)g carbs · \(meal.energy) kcal")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.quietInk)
            }
            .padding(.horizontal, 3)
            .padding(.bottom, 2)
        }
    }
}

private struct MealDetailCurtain: View {
    let meal: Meal
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            Capsule().fill(Color.rule).frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.title)
                        .font(DiafitType.title)
                        .foregroundStyle(Color.ink)
                    Text(meal.subtitle)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.quietInk)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 30, height: 30)
                        .background(Color.mist.opacity(0.55), in: Circle())
                }
                .buttonStyle(PressableStyle(pressedScale: 0.85))
            }

            HStack(spacing: 8) {
                AtlasMetric(value: "\(meal.energy)", label: "kcal", tint: .ink)
                AtlasMetric(value: "\(meal.carbs)g", label: "carbs", tint: .coral)
                AtlasMetric(value: "\(meal.protein)g", label: "protein", tint: .lime)
                AtlasMetric(value: "\(meal.fat)g", label: "fat", tint: .saffron)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 19)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 25, y: 13)
    }
}

private struct AtlasMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.quietInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// `UIVisualEffectView` gives the overlay a stable blur when the SwiftUI root
/// is being transformed by the matched-geometry animation.
private struct VisualEffectBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct MealAtlasView_Previews: PreviewProvider {
    static var previews: some View { MealAtlasPreview() }

    private struct MealAtlasPreview: View {
        @State private var isPresented = true
        @Namespace private var namespace

        var body: some View {
            MealAtlasView(day: DiaryStore.preview.days.last!, isPresented: $isPresented, mealNamespace: namespace)
        }
    }
}
