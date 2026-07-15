import SwiftUI
import UIKit

/// The review card is deliberately part of the conversation. It makes the
/// uncertainty behind a photo or phrase visible, but keeps the first read
/// focused on food components, serving, carbohydrates, and confirmation.
struct MealAnalysisReviewCard: View {
    let draft: MealAnalysisDraft
    let onUpdate: (MealAnalysisDraft) -> Void
    let onConfirm: (MealAnalysisDraft) -> Void
    let onDiscard: () -> Void
    let onRetryVisual: (MealAnalysisDraft) -> Void
    let confirmationTitle: String

    @State private var editableDraft: MealAnalysisDraft
    @State private var showsDetail = false
    @State private var componentQuery = ""

    private let catalog = IndianFoodCatalogService()
    private let portions = StandardPortionEstimationService()
    private let nutrition = CatalogNutritionLookupService()
    private let glycaemic = CatalogGlycaemicDataService()
    private let validation = DefaultNutritionValidationService()

    init(
        draft: MealAnalysisDraft,
        onUpdate: @escaping (MealAnalysisDraft) -> Void,
        onConfirm: @escaping (MealAnalysisDraft) -> Void,
        onDiscard: @escaping () -> Void,
        onRetryVisual: @escaping (MealAnalysisDraft) -> Void = { _ in },
        confirmationTitle: String = "Confirm estimate"
    ) {
        self.draft = draft
        self.onUpdate = onUpdate
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        self.onRetryVisual = onRetryVisual
        self.confirmationTitle = confirmationTitle
        _editableDraft = State(initialValue: draft)
    }

    private var result: MealAnalysisResult { editableDraft.result }

    private var highImpactQuestionsAnswered: Bool {
        result.clarificationQuestions
            .filter { $0.impactLevel == .high }
            .allSatisfy { $0.answer != nil }
    }

    private var nutritionIsSafeToConfirm: Bool {
        result.nutritionValidation?.isApproved ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let image = editableDraft.transientImageData.flatMap(UIImage.init(data:)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 178)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Text("ORIGINAL · REVIEW ONLY")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.42), in: Capsule())
                            .padding(10)
                    }
            }

            if let request = result.visualRequest {
                MealVisualRequestStatus(
                    request: request,
                    items: result.detectedItems,
                    hasOriginalPhoto: editableDraft.transientImageData != nil,
                    retry: retryVisualRequest
                )
            }

            if result.detectedItems.isEmpty {
                EmptyAnalysisState(query: $componentQuery, addComponent: addComponent)
            } else {
                VStack(spacing: 8) {
                    ForEach(result.detectedItems) { item in
                        DetectedItemEditor(
                            item: item,
                            alternatives: alternatives(for: item),
                            quantityChanged: { quantity in changeQuantity(quantity, for: item.id) },
                            unitChanged: { unit in changeUnit(unit, for: item.id) },
                            foodChanged: { id in changeFood(id, for: item.id) },
                            remove: { remove(item.id) }
                        )
                    }
                }
            }

            summary

            if !result.clarificationQuestions.isEmpty {
                questions
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsDetail.toggle() }
            } label: {
                HStack {
                    Text(showsDetail ? "Hide assumptions" : "See assumptions & sources")
                    Spacer()
                    Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                }
                .font(DiafitType.caption)
                .foregroundStyle(Color.quietInk)
            }
            .buttonStyle(.plain)

            if showsDetail {
                AnalysisEvidence(result: result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                Button("Discard", role: .destructive, action: onDiscard)
                    .buttonStyle(OutlineCapsuleStyle())
                Button(action: { onConfirm(editableDraft) }) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark")
                    Text(highImpactQuestionsAnswered && nutritionIsSafeToConfirm ? confirmationTitle : "Answer to confirm")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConfirmMealStyle())
                .disabled(result.detectedItems.isEmpty || !highImpactQuestionsAnswered || !nutritionIsSafeToConfirm)
                .opacity(result.detectedItems.isEmpty || !highImpactQuestionsAnswered || !nutritionIsSafeToConfirm ? 0.46 : 1)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.rule.opacity(0.72), lineWidth: 0.8))
        .onChange(of: draft.result.visualRequest) { _, visualRequest in
            editableDraft.result.visualRequest = visualRequest
            editableDraft.result.generatedVisualAsset = draft.result.generatedVisualAsset
            editableDraft.result.imageType = draft.result.imageType
        }
        .shadow(color: .black.opacity(0.055), radius: 17, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "camera.metering.spot")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 32, height: 32)
                .background(Color.lime.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("REVIEW BEFORE LOGGING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.05)
                    .foregroundStyle(Color.quietInk)
                Text(result.detectedItems.isEmpty ? "Let’s identify the plate" : "A likely reading of this meal")
                    .font(DiafitType.title)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            ConfidenceMark(confidence: result.overallConfidence)
        }
    }

    private var summary: some View {
        HStack(spacing: 7) {
            SummaryMetric(value: NutritionFormatter.energy(result.mealTotals.caloriesKcal), label: "kcal", tint: .ink)
            SummaryMetric(value: NutritionFormatter.grams(result.mealTotals.carbohydrateGrams), label: "carbs", tint: .coral)
            SummaryMetric(value: NutritionFormatter.grams(result.mealTotals.fibreGrams), label: "fibre", tint: .lime)
            SummaryMetric(value: NutritionFormatter.grams(result.mealTotals.proteinGrams), label: "protein", tint: .saffron)
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A QUICK CHECK")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.quietInk)
            ForEach(result.clarificationQuestions) { question in
                VStack(alignment: .leading, spacing: 7) {
                    Text(question.question)
                        .font(DiafitType.caption)
                        .foregroundStyle(Color.ink)
                    FlowLayout(spacing: 7) {
                        ForEach(question.options, id: \.self) { option in
                            Button(option) { answer(option, to: question.id) }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(question.answer == option ? Color.paper : Color.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(question.answer == option ? Color.ink : Color.mist.opacity(0.62), in: Capsule())
                                .buttonStyle(PressableStyle(pressedScale: 0.94))
                        }
                    }
                }
                .padding(11)
                .background(Color.mist.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func alternatives(for item: DetectedFoodItem) -> [AlternativeFoodMatch] {
        [AlternativeFoodMatch(canonicalFoodId: item.canonicalFoodId, displayName: item.displayName, confidence: item.confidence)] + item.alternatives
    }

    private func changeQuantity(_ quantity: Double, for id: UUID) {
        guard let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == id }) else { return }
        editableDraft.result.detectedItems[index].quantity = max(0.25, quantity)
        recalculate()
    }

    private func changeUnit(_ unit: ServingUnit, for id: UUID) {
        guard let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == id }) else { return }
        editableDraft.result.detectedItems[index].servingUnit = unit
        recalculate()
    }

    private func changeFood(_ canonicalID: String, for id: UUID) {
        guard let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == id }),
              let definition = catalog.food(canonicalID: canonicalID) else { return }
        let original = editableDraft.result.detectedItems[index]
        editableDraft.result.detectedItems[index] = item(from: definition, preserving: original)
        recalculate()
    }

    private func remove(_ id: UUID) {
        editableDraft.result.detectedItems.removeAll { $0.id == id }
        recalculate()
    }

    private func addComponent() {
        guard let definition = catalog.normalise(componentQuery) else { return }
        let original = DetectedFoodItem(
            id: UUID(), canonicalFoodId: definition.canonicalId, displayName: definition.canonicalName,
            regionalName: definition.regionalNames.first, category: definition.category, confidence: .low,
            alternatives: [], quantity: definition.standardServing?.quantity ?? 1,
            servingUnit: definition.standardServing?.unit ?? .serving, estimatedWeightGrams: nil,
            visibleIngredients: [], inferredIngredients: definition.commonIngredients, possibleIngredients: [],
            preparationMethod: definition.commonPreparationMethods.first, nutrition: .unavailable,
            glycaemicInformation: .unavailable, assumptions: ["Added by you; recipe may vary."], warnings: [], boundingRegion: nil,
            nutritionProvenance: .unavailable
        )
        editableDraft.result.detectedItems.append(item(from: definition, preserving: original))
        componentQuery = ""
        recalculate()
    }

    private func answer(_ value: String, to questionID: UUID) {
        guard let index = editableDraft.result.clarificationQuestions.firstIndex(where: { $0.id == questionID }) else { return }
        editableDraft.result.clarificationQuestions[index].answer = value
        recalculate()
    }

    private func retryVisualRequest() {
        editableDraft.result.visualRequest = MealVisualRequestBuilder().make(
            mealID: editableDraft.result.analysisId,
            items: editableDraft.result.detectedItems,
            clarificationQuestions: editableDraft.result.clarificationQuestions
        )
        editableDraft.result.generatedVisualAsset = nil
        onUpdate(editableDraft)
        onRetryVisual(editableDraft)
    }

    private func item(from definition: IndianFoodDefinition, preserving original: DetectedFoodItem) -> DetectedFoodItem {
        DetectedFoodItem(
            id: original.id,
            canonicalFoodId: definition.canonicalId,
            displayName: definition.canonicalName,
            regionalName: definition.regionalNames.first,
            category: definition.category,
            confidence: definition.confidence == .unknown ? .low : definition.confidence,
            alternatives: catalog.foods.filter { $0.category == definition.category && $0.id != definition.id }.prefix(2).map {
                AlternativeFoodMatch(canonicalFoodId: $0.canonicalId, displayName: $0.canonicalName, confidence: .low)
            },
            quantity: original.quantity,
            servingUnit: original.servingUnit,
            estimatedWeightGrams: original.estimatedWeightGrams,
            visibleIngredients: original.visibleIngredients,
            inferredIngredients: definition.commonIngredients,
            possibleIngredients: original.possibleIngredients,
            preparationMethod: definition.commonPreparationMethods.first,
            nutrition: original.nutrition,
            glycaemicInformation: original.glycaemicInformation,
            assumptions: original.assumptions,
            warnings: original.warnings,
            boundingRegion: original.boundingRegion,
            nutritionProvenance: original.nutritionProvenance,
            rawNutrition: original.rawNutrition,
            nutritionValidation: original.nutritionValidation,
            matchedAlias: original.matchedAlias,
            confidenceScore: original.confidenceScore,
            modifiers: original.modifiers,
            supplementProfile: original.supplementProfile
        )
    }

    private func recalculate() {
        let previousVisualRequest = editableDraft.result.visualRequest
        applyVariationSelections()
        applySupplementSelections()
        for index in editableDraft.result.detectedItems.indices {
            let item = editableDraft.result.detectedItems[index]
            guard let definition = catalog.food(canonicalID: item.canonicalFoodId) else { continue }
            let weight = portions.estimatedWeight(quantity: item.quantity, unit: item.servingUnit, food: definition)
            let lookup = nutrition.nutrition(for: definition, estimatedWeightGrams: weight)
            let resolvedValues = nutritionIncludingShakeBase(lookup.values, profile: item.supplementProfile)
            let report = validation.validate(
                rawValues: resolvedValues,
                canonicalFoodID: definition.canonicalId,
                quantity: item.quantity,
                servingUnit: item.servingUnit,
                estimatedWeightGrams: weight
            )
            editableDraft.result.detectedItems[index].estimatedWeightGrams = weight
            editableDraft.result.detectedItems[index].rawNutrition = resolvedValues
            editableDraft.result.detectedItems[index].nutrition = report.safeValues ?? .unavailable
            editableDraft.result.detectedItems[index].nutritionValidation = report
            editableDraft.result.detectedItems[index].nutritionProvenance = lookup.provenance
            editableDraft.result.detectedItems[index].glycaemicInformation = glycaemic.information(
                for: definition,
                availableCarbohydrateGrams: report.safeValues?.availableCarbohydrateGrams
            )
        }

        applyClarificationEffects()
        let totals = NutritionValues.total(of: editableDraft.result.detectedItems.map(\.nutrition))
        let allValuesSupported = !editableDraft.result.detectedItems.isEmpty
            && editableDraft.result.detectedItems.allSatisfy { !$0.nutrition.isEmpty }
        let totalReport = validation.validate(rawValues: totals, canonicalFoodID: nil, quantity: nil, servingUnit: nil, estimatedWeightGrams: nil)
        let report = allValuesSupported ? totalReport : NutritionValidationReport(
            status: .requiresClarification,
            rawValues: totals,
            safeValues: nil,
            issues: totalReport.issues + [.init(
                code: .unavailableNutrition,
                severity: .blocking,
                message: "Choose a supported food variation before nutrition can be saved."
            )]
        )
        editableDraft.result.mealTotals = report.safeValues ?? .unavailable
        editableDraft.result.nutritionValidation = report
        editableDraft.result.nutritionProvenance = allValuesSupported
            ? NutritionProvenance(kind: .curatedRecipeEstimate, dataSource: "Bundled recipe estimate — recipe may vary", dataVersion: catalog.version, confidence: .low)
            : .unavailable
        let nextVisualRequest = MealVisualRequestBuilder().make(
            mealID: editableDraft.result.analysisId,
            items: editableDraft.result.detectedItems,
            clarificationQuestions: editableDraft.result.clarificationQuestions
        )
        let visualChanged = nextVisualRequest?.cacheKey != previousVisualRequest?.cacheKey
        if visualChanged {
            editableDraft.result.visualRequest = nextVisualRequest
            editableDraft.result.generatedVisualAsset = nil
        } else {
            editableDraft.result.visualRequest = previousVisualRequest
        }
        editableDraft.result.warnings = editableDraft.result.warnings.filter { !$0.contains("Nutrition needs confirmation") }
        if !report.isApproved {
            editableDraft.result.warnings.append("Nutrition needs confirmation before it can affect your daily totals.")
        }
        onUpdate(editableDraft)
        if visualChanged, nextVisualRequest?.state != .waitingForClarification {
            onRetryVisual(editableDraft)
        }
    }

    private func applySupplementSelections() {
        for question in editableDraft.result.clarificationQuestions {
            guard question.question.contains("How many scoops"),
                  let answer = question.answer,
                  let itemID = question.relatedFoodItemId,
                  let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == itemID }),
                  var profile = editableDraft.result.detectedItems[index].supplementProfile else { continue }
            let scoops: Double = answer.contains("2 scoop") ? 2 : 1
            profile.base = answer.contains("milk") ? .milk : .water
            profile.servingUnit = .scoop
            profile.servingSizeGrams = (profile.gramsPerScoop ?? 30) * scoops
            profile.isUserConfirmed = true
            editableDraft.result.detectedItems[index].quantity = scoops
            editableDraft.result.detectedItems[index].servingUnit = .scoop
            editableDraft.result.detectedItems[index].supplementProfile = profile
            editableDraft.result.detectedItems[index].modifiers = Array(Set(
                editableDraft.result.detectedItems[index].modifiers.filter { $0 != "water" && $0 != "milk" } + [profile.base.rawValue]
            )).sorted()
            editableDraft.result.detectedItems[index].assumptions = [
                "Confirmed \(scoops.formatted(.number.precision(.fractionLength(0)))) scoop(s) mixed with \(profile.base.displayName).",
                "Swap in your saved or scanned product label whenever it is available."
            ]
        }
    }

    private func nutritionIncludingShakeBase(_ powder: NutritionValues, profile: SupplementProductProfile?) -> NutritionValues {
        guard profile?.base == .milk,
              let milk = catalog.normalise("milk") else { return powder }
        let milkWeight = milk.standardServing?.grams ?? 240
        let milkValues = nutrition.nutrition(for: milk, estimatedWeightGrams: milkWeight).values
        return NutritionValues.total(of: [powder, milkValues])
    }

    private func applyVariationSelections() {
        for question in editableDraft.result.clarificationQuestions {
            guard let answer = question.answer,
                  let itemID = question.relatedFoodItemId,
                  let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == itemID }),
                  let canonicalID = canonicalVariation(for: answer, question: question.question),
                  let definition = catalog.food(canonicalID: canonicalID) else { continue }
            editableDraft.result.detectedItems[index] = item(from: definition, preserving: editableDraft.result.detectedItems[index])
        }
    }

    private func canonicalVariation(for answer: String, question: String) -> String? {
        if question.contains("plain black coffee") {
            return ["Black": "black-coffee", "Milk": "coffee-with-milk", "Milk + sugar": "coffee-with-milk-and-sugar"][answer]
        }
        if question.contains("Was the chai sweetened") {
            return ["No milk or sugar": "plain-tea", "Milk, no sugar": "chai-with-milk", "Milk + sugar": "chai-with-milk-and-sugar"][answer]
        }
        if question.contains("Was the tea plain") {
            return ["Plain": "plain-tea", "Milk, no sugar": "chai-with-milk", "Milk + sugar": "chai-with-milk-and-sugar"][answer]
        }
        if question.contains("Was the paratha") {
            return ["Plain": "plain-paratha", "Aloo / stuffed": "aloo-paratha", "Buttered": "buttered-paratha"][answer]
        }
        return nil
    }

    /// Corrections only adjust values for explicitly answered high-impact recipe
    /// questions. They stay estimates and remain visible in the assumptions.
    private func applyClarificationEffects() {
        for question in editableDraft.result.clarificationQuestions {
            guard let answer = question.answer,
                  let itemID = question.relatedFoodItemId,
                  let index = editableDraft.result.detectedItems.firstIndex(where: { $0.id == itemID }) else { continue }
            var item = editableDraft.result.detectedItems[index]
            if question.question.contains("oil, ghee, butter, or cream") {
                let extraFat: Double = answer == "Some" ? 5 : (answer == "A generous amount" ? 15 : 0)
                item.nutrition.fatGrams = (item.nutrition.fatGrams ?? 0) + extraFat
                item.nutrition.caloriesKcal = (item.nutrition.caloriesKcal ?? 0) + extraFat * 9
                item.assumptions = ["Adjusted for your answer about added fat; still an estimate."]
            } else if question.question.contains("sweetened"), answer == "Yes" {
                item.nutrition.carbohydrateGrams = (item.nutrition.carbohydrateGrams ?? 0) + 8
                item.nutrition.totalSugarGrams = (item.nutrition.totalSugarGrams ?? 0) + 8
                item.nutrition.addedSugarGrams = (item.nutrition.addedSugarGrams ?? 0) + 8
                item.nutrition.caloriesKcal = (item.nutrition.caloriesKcal ?? 0) + 32
                item.assumptions = ["Adjusted for a typical added-sugar amount; still an estimate."]
            }
            editableDraft.result.detectedItems[index] = item
        }
    }
}

private struct MealVisualRequestStatus: View {
    let request: MealVisualRequest
    let items: [DetectedFoodItem]
    let hasOriginalPhoto: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            visualGlyph
                .frame(width: 38, height: 38)
                .background(Color.lime.opacity(0.36), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(Color.quietInk)
                Text(detail)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if request.state == .failed || request.state == .deterministicFallback {
                Button("Retry", action: retry)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(Color.paper, in: Capsule())
                    .accessibilityLabel("Retry meal image")
            }
        }
        .padding(11)
        .background(Color.mist.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meal image \(title.lowercased()): \(detail)")
    }

    private var title: String {
        switch request.state {
        case .queued: return "MEAL VISUAL PREPARING"
        case .waitingForClarification: return "VISUAL WAITING FOR DETAILS"
        case .deterministicFallback: return "MEAL VISUAL READY"
        case .ready: return "EDITORIAL MEAL VISUAL READY"
        case .failed: return "IMAGE UNAVAILABLE"
        }
    }

    private var detail: String {
        switch request.state {
        case .queued: return "Building a quantity-aware food composition."
        case .waitingForClarification: return "Confirm the shake base and scoop count to make the visual accurate."
        case .deterministicFallback:
            return "A verified component composition is shown while image generation is unavailable."
        case .ready:
            return "The quantity-aware editorial image is saved with this meal."
        case .failed:
            return hasOriginalPhoto
                ? "Retry generation or keep your original photo."
                : "Retry generation, or add a meal photo from the composer."
        }
    }

    @ViewBuilder
    private var visualGlyph: some View {
        if items.contains(where: { $0.category == .egg || $0.canonicalFoodId.contains("egg") }) {
            Image(systemName: "circle.grid.cross.fill")
                .foregroundStyle(Color.ink)
        } else if items.contains(where: { $0.category == .supplement }) {
            Image(systemName: "waterbottle.fill")
                .foregroundStyle(Color.ink)
        } else {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.ink)
        }
    }
}

private struct DetectedItemEditor: View {
    let item: DetectedFoodItem
    let alternatives: [AlternativeFoodMatch]
    let quantityChanged: (Double) -> Void
    let unitChanged: (ServingUnit) -> Void
    let foodChanged: (String) -> Void
    let remove: () -> Void

    @State private var quantityText: String

    init(
        item: DetectedFoodItem,
        alternatives: [AlternativeFoodMatch],
        quantityChanged: @escaping (Double) -> Void,
        unitChanged: @escaping (ServingUnit) -> Void,
        foodChanged: @escaping (String) -> Void,
        remove: @escaping () -> Void
    ) {
        self.item = item
        self.alternatives = alternatives
        self.quantityChanged = quantityChanged
        self.unitChanged = unitChanged
        self.foodChanged = foodChanged
        self.remove = remove
        _quantityText = State(initialValue: item.quantity.formatted(.number.precision(.fractionLength(0...1))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Menu {
                    ForEach(alternatives) { alternative in
                        Button(alternative.displayName) { foodChanged(alternative.canonicalFoodId) }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.displayName)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                }
                Spacer()
                ConfidenceMark(confidence: item.confidence)
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(Color.quietInk)
                }
                .accessibilityLabel("Remove \(item.displayName)")
            }

            HStack(spacing: 8) {
                TextField("Quantity", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .font(DiafitType.caption)
                    .frame(width: 42)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 7)
                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit { commitQuantity() }
                    .onChange(of: quantityText) { _, newValue in
                        guard let value = Double(newValue.replacingOccurrences(of: ",", with: ".")) else { return }
                        quantityChanged(value)
                    }
                    .accessibilityLabel("\(item.displayName) quantity")
                Menu(item.servingUnit.singularDisplayName) {
                    ForEach(ServingUnit.allCases, id: \.self) { unit in
                        Button(unit.singularDisplayName) { unitChanged(unit) }
                    }
                }
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.paper, in: Capsule())
                .accessibilityLabel("Change \(item.displayName) serving unit")
                Spacer()
                Text(NutritionFormatter.grams(item.nutrition.carbohydrateGrams) + " carbs")
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.coral)
            }
        }
        .padding(12)
        .background(Color.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func commitQuantity() {
        if let value = Double(quantityText.replacingOccurrences(of: ",", with: ".")) {
            quantityChanged(value)
        }
    }
}

private struct EmptyAnalysisState: View {
    @Binding var query: String
    let addComponent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("I don’t want to guess from the photo alone.")
                .font(DiafitType.body)
                .foregroundStyle(Color.ink)
            HStack(spacing: 8) {
                TextField("e.g. rajma with rice", text: $query)
                    .font(DiafitType.caption)
                    .padding(10)
                    .background(Color.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button(action: addComponent) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.paper)
                        .frame(width: 34, height: 34)
                        .background(Color.ink, in: Circle())
                }
                .accessibilityLabel("Add meal component")
            }
        }
        .padding(13)
        .background(Color.mist.opacity(0.38), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct AnalysisEvidence: View {
    let result: MealAnalysisResult

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            DetailLine(label: "Source", value: result.nutritionProvenance.dataSource)
            DetailLine(label: "Confidence", value: result.overallConfidence.displayName)
            DetailLine(label: "Glycaemic data", value: result.detectedItems.allSatisfy { $0.glycaemicInformation.glycaemicIndex == nil } ? "Not available" : "Shown where supported")
            ForEach(result.assumptions, id: \.self) { DetailLine(label: "Assumption", value: $0) }
            ForEach(result.warnings, id: \.self) { warning in
                Text(warning)
                    .font(DiafitType.caption)
                    .foregroundStyle(Color.coral)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(Color.mist.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DetailLine: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(Color.quietInk)
            Text(value)
                .font(DiafitType.caption)
                .foregroundStyle(Color.ink)
                .lineSpacing(2)
        }
    }
}

private struct ConfidenceMark: View {
    let confidence: ConfidenceLevel
    var body: some View {
        Text(confidence == .high ? "HIGH" : confidence == .medium ? "LIKELY" : "CHECK")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(confidence == .high ? Color.ink : Color.quietInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(confidence == .high ? Color.lime.opacity(0.55) : Color.mist.opacity(0.75), in: Capsule())
    }
}

private struct SummaryMetric: View {
    let value: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.quietInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("meal-total-\(label)")
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct ConfirmMealStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.paper)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(Color.ink.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct OutlineCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.quietInk)
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(Color.mist.opacity(configuration.isPressed ? 0.68 : 0.45), in: Capsule())
    }
}

enum NutritionFormatter {
    static func grams(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "g"
    }

    static func energy(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if lineWidth + size.width > width, lineWidth > 0 {
                height += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: height + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: origin, proposal: ProposedViewSize(size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
