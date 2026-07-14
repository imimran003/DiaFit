import XCTest
@testable import Diafit

final class FoodAnalysisTests: XCTestCase {
    private var catalog: IndianFoodCatalogService {
        IndianFoodCatalogService(bundle: Bundle(for: FoodAnalysisTests.self))
    }

    func testIndianAliasesNormaliseToCanonicalFood() {
        XCTAssertEqual(catalog.normalise("chapati")?.canonicalId, "roti")
        XCTAssertEqual(catalog.normalise("dahi")?.canonicalId, "dahi")
        XCTAssertEqual(catalog.normalise("chickpea curry")?.canonicalId, "chole")
        XCTAssertEqual(catalog.normalise("flattened rice")?.canonicalId, "poha")
        XCTAssertEqual(catalog.normalise("clarified butter")?.canonicalId, "ghee")
    }

    func testCatalogCoversRequestedRegionalGroups() {
        XCTAssertEqual(catalog.normalise("neer dosa")?.category, .bread)
        XCTAssertEqual(catalog.normalise("mutton biryani")?.category, .rice)
        XCTAssertEqual(catalog.normalise("sambar")?.category, .lentilOrLegume)
        XCTAssertEqual(catalog.normalise("undhiyu")?.category, .vegetarianCurry)
        XCTAssertEqual(catalog.normalise("rogan josh")?.category, .nonVegetarian)
        XCTAssertEqual(catalog.normalise("pani puri")?.category, .breakfastOrSnack)
        XCTAssertEqual(catalog.normalise("sugarcane juice")?.category, .dessertOrDrink)
    }

    func testMixedMealStaysComponentBased() {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let analysis = engine.makeAnalysis(description: "Dosa with sambar and coconut chutney")
        XCTAssertEqual(Set(analysis.detectedItems.map(\.canonicalFoodId)), Set(["dosa", "sambar", "coconut-chutney"]))
        XCTAssertEqual(analysis.imageType, .noImage)
        XCTAssertTrue(analysis.warnings.contains { $0.contains("incomplete") })
    }

    func testServingConversionAndNutritionScaling() {
        let roti = try! XCTUnwrap(catalog.normalise("roti"))
        let portions = StandardPortionEstimationService()
        let weight = portions.estimatedWeight(quantity: 2, unit: .roti, food: roti)
        XCTAssertEqual(weight, 70)

        let lookup = CatalogNutritionLookupService().nutrition(for: roti, estimatedWeightGrams: weight)
        XCTAssertEqual(lookup.values.carbohydrateGrams ?? 0, 43.05, accuracy: 0.01)
        XCTAssertEqual(lookup.provenance.kind, .curatedRecipeEstimate)
    }

    func testGlycaemicLoadNeedsBothInputs() {
        let unavailable = GlycaemicInformation.calculate(index: 55, source: nil, availableCarbohydrate: 20)
        XCTAssertNil(unavailable.glycaemicLoad)
        XCTAssertEqual(unavailable.unavailableReason, "Not available for this preparation")

        let supported = GlycaemicInformation.calculate(index: 55, source: "Test source", availableCarbohydrate: 20)
        XCTAssertEqual(supported.glycaemicLoad ?? 0, 11, accuracy: 0.001)
    }

    func testUnknownNutritionRemainsUnavailable() {
        let chutney = try! XCTUnwrap(catalog.normalise("coconut chutney"))
        let lookup = CatalogNutritionLookupService().nutrition(for: chutney, estimatedWeightGrams: 40)
        XCTAssertTrue(lookup.values.isEmpty)
        XCTAssertEqual(lookup.provenance.kind, .unavailable)
    }

    /// Regression: the legacy freeform fallback classified any unrecognised
    /// note as a 470 kcal bowl. A plain black coffee must never inherit that
    /// generic meal profile.
    func testBlackCoffeeNeverUsesGenericHighCalorieMealFallback() {
        let meal = LocalNutritionService().estimate(for: "I had black coffee", at: .now)

        XCTAssertLessThan(meal.energy, 25)
        XCTAssertNotEqual(meal.artwork, .bowl)
    }

    /// Regression: a multi-component Indian meal must retain a visual identity
    /// linked to its components rather than receiving the unrelated bowl image.
    func testChaiAndParathaNeverUsesUnrelatedBowlArtwork() {
        let meal = LocalNutritionService().estimate(for: "I had chai and paratha", at: .now)

        XCTAssertTrue(meal.title.localizedCaseInsensitiveContains("chai"))
        XCTAssertTrue(meal.title.localizedCaseInsensitiveContains("paratha"))
        XCTAssertNotEqual(meal.artwork, .bowl)
    }

    func testBlackCoffeePipelineUsesExactUnsweetenedVariationAndSafeNutrition() {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "I had unsweetened black coffee")

        XCTAssertEqual(result.detectedItems.map(\.canonicalFoodId), ["black-coffee"])
        XCTAssertTrue(result.nutritionValidation?.isApproved == true)
        XCTAssertLessThan(result.mealTotals.caloriesKcal ?? .infinity, 5)
        XCTAssertTrue(result.clarificationQuestions.isEmpty)
        XCTAssertTrue(result.detectedItems[0].nutritionProvenance.dataSource.contains("USDA FoodData Central"))
    }

    func testChaiAndParathaStaysComponentBasedUntilVariationsAreConfirmed() {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "I had chai and paratha")
        let visual = MealVisualIdentityFactory().make(mealID: UUID(), result: result, artwork: .neutral)
        let prompt = MealVisualIdentityFactory().editorialPrompt(for: visual)

        XCTAssertEqual(Set(result.detectedItems.map(\.canonicalFoodId)), Set(["chai", "paratha"]))
        XCTAssertFalse(result.nutritionValidation?.isApproved ?? true)
        XCTAssertEqual(result.clarificationQuestions.count, 2)
        XCTAssertTrue(result.clarificationQuestions.contains { $0.question.contains("chai sweetened") })
        XCTAssertTrue(result.clarificationQuestions.contains { $0.question.contains("paratha plain") })
        XCTAssertTrue(prompt.contains("chai"))
        XCTAssertTrue(prompt.contains("paratha"))
        XCTAssertTrue(prompt.contains("No salad"))
        XCTAssertEqual(visual.source, .deterministicPlaceholder)
    }

    func testBeverageVariationsNormaliseToCanonicalRecords() {
        let examples: [(String, String)] = [
            ("black coffee", "black-coffee"),
            ("unsweetened black coffee", "black-coffee"),
            ("coffee with one teaspoon sugar", "coffee-with-sugar"),
            ("coffee with milk", "coffee-with-milk"),
            ("latte", "latte"),
            ("cappuccino", "cappuccino"),
            ("plain tea", "plain-tea"),
            ("chai", "chai"),
            ("chai with milk and sugar", "chai-with-milk-and-sugar"),
            ("green tea", "green-tea"),
            ("buttermilk", "buttermilk"),
            ("sweet lassi", "sweet-lassi"),
            ("unsweetened lassi", "unsweetened-lassi")
        ]

        for (input, expectedID) in examples {
            XCTAssertEqual(catalog.matches(in: input).map(\.canonicalId), [expectedID], input)
        }
    }

    func testAmbiguousFoodNotesAreReviewDraftsRatherThanSavedMeals() {
        let service = LocalNutritionService(analysisEngine: LocalMealAnalysisEngine(catalog: catalog))
        for note in ["coffee", "tea", "paratha", "rice", "sandwich", "juice"] {
            guard case .review(let draft) = service.resolve(note: note, at: .now) else {
                return XCTFail("\(note) should never silently resolve to a saved meal")
            }
            XCTAssertFalse(draft.result.detectedItems.isEmpty && draft.result.nutritionValidation?.isApproved == true)
        }
    }

    func testIndianMixedMealFixturesRemainSeparatedAndScaleQuantitiesOnce() {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let expectedComponents: [(String, Set<String>)] = [
            ("roti and dal", ["roti", "dal"]),
            ("rajma rice", ["rajma", "steamed-rice"]),
            ("dosa with sambar and coconut chutney", ["dosa", "sambar", "coconut-chutney"]),
            ("idli with sambar", ["idli", "sambar"]),
            ("paneer butter masala with naan", ["paneer-butter-masala", "naan"]),
            ("chicken biryani with raita", ["chicken-biryani", "raita"]),
            ("poha", ["poha"]),
            ("mixed thali", ["mixed-thali"])
        ]

        for (input, expected) in expectedComponents {
            XCTAssertEqual(Set(engine.makeAnalysis(description: input).detectedItems.map(\.canonicalFoodId)), expected, input)
        }

        let twoParathas = engine.makeAnalysis(description: "chai with two aloo parathas")
        XCTAssertEqual(twoParathas.detectedItems.first(where: { $0.canonicalFoodId == "aloo-paratha" })?.quantity, 2)
    }

    func testCentralNutritionGuardRejectsImplausibleBlackCoffeeAndMacroMismatch() {
        let validator = DefaultNutritionValidationService()
        let implausibleCoffee = validator.validate(
            rawValues: NutritionValues(caloriesKcal: 470, proteinGrams: 20, carbohydrateGrams: 48, fatGrams: 18),
            canonicalFoodID: "black-coffee",
            quantity: 1,
            servingUnit: .cup,
            estimatedWeightGrams: 240
        )
        XCTAssertFalse(implausibleCoffee.isApproved)
        XCTAssertNil(implausibleCoffee.safeValues)
        XCTAssertTrue(implausibleCoffee.issues.contains { $0.code == .implausibleBeverageEnergy })

        let macroMismatch = validator.validate(
            rawValues: NutritionValues(caloriesKcal: 800, proteinGrams: 1, carbohydrateGrams: 2, fatGrams: 1),
            canonicalFoodID: "test-food",
            quantity: 1,
            servingUnit: .serving,
            estimatedWeightGrams: 100
        )
        XCTAssertFalse(macroMismatch.isApproved)
        XCTAssertTrue(macroMismatch.issues.contains { $0.code == .energyMismatch })
    }

    func testPortionUnitsAndNutritionScalingStayFiniteAndMonotonic() throws {
        let roti = try XCTUnwrap(catalog.normalise("roti"))
        let ghee = try XCTUnwrap(catalog.normalise("ghee"))
        let portions = StandardPortionEstimationService()
        XCTAssertEqual(portions.estimatedWeight(quantity: 1, unit: .cup, food: roti), 240)
        XCTAssertEqual(portions.estimatedWeight(quantity: 1, unit: .teaspoon, food: ghee), 5)
        XCTAssertEqual(portions.estimatedWeight(quantity: 1, unit: .tablespoon, food: ghee), 15)

        let lookup = CatalogNutritionLookupService()
        var previousCalories = -Double.infinity
        for quantity in stride(from: 0.1, through: 20, by: 0.1) {
            let grams = try XCTUnwrap(portions.estimatedWeight(quantity: quantity, unit: .roti, food: roti))
            let values = lookup.nutrition(for: roti, estimatedWeightGrams: grams).values
            let calories = try XCTUnwrap(values.caloriesKcal)
            XCTAssertTrue(calories.isFinite)
            XCTAssertGreaterThanOrEqual(calories, previousCalories)
            XCTAssertGreaterThanOrEqual(values.carbohydrateGrams ?? -1, 0)
            previousCalories = calories
        }
    }

    func testVisualIdentityIsDeterministicCollisionResistantAndBoundToMeal() {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let chaiParatha = engine.makeAnalysis(description: "chai and paratha")
        let blackCoffee = engine.makeAnalysis(description: "black coffee")
        let factory = MealVisualIdentityFactory()
        let first = factory.make(mealID: UUID(), result: chaiParatha, artwork: .neutral)
        let repeated = factory.make(mealID: UUID(), result: chaiParatha, artwork: .neutral)
        let coffee = factory.make(mealID: UUID(), result: blackCoffee, artwork: .neutral)

        XCTAssertEqual(first.cacheKey, repeated.cacheKey)
        XCTAssertNotEqual(first.cacheKey, coffee.cacheKey)
        XCTAssertNotEqual(first.mealID, repeated.mealID)
        XCTAssertEqual(first.canonicalFoodIDs, ["chai", "paratha"])
    }

    func testVisualRequestLedgerRejectsStaleCrossMealAndDeletedResponses() async {
        let ledger = MealVisualRequestLedger()
        let firstMeal = UUID()
        let secondMeal = UUID()
        let firstRequest = UUID()
        let replacementRequest = UUID()
        let secondRequest = UUID()

        await ledger.begin(mealID: firstMeal, cacheKey: "first", requestID: firstRequest)
        let firstCanApply = await ledger.canApply(mealID: firstMeal, cacheKey: "first", requestID: firstRequest)
        let crossMealCanApply = await ledger.canApply(mealID: secondMeal, cacheKey: "first", requestID: firstRequest)
        XCTAssertTrue(firstCanApply)
        XCTAssertFalse(crossMealCanApply)

        await ledger.begin(mealID: firstMeal, cacheKey: "replacement", requestID: replacementRequest)
        let staleCanApply = await ledger.canApply(mealID: firstMeal, cacheKey: "first", requestID: firstRequest)
        XCTAssertFalse(staleCanApply)
        await ledger.begin(mealID: secondMeal, cacheKey: "second", requestID: secondRequest)
        await ledger.delete(mealID: secondMeal)
        let deletedCanApply = await ledger.canApply(mealID: secondMeal, cacheKey: "second", requestID: secondRequest)
        XCTAssertFalse(deletedCanApply)
    }

    func testAnalysisCodableRoundTripAndDailyTotalRecalculation() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "black coffee")
        let decoded = try JSONDecoder().decode(MealAnalysisResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.detectedItems.map(\.canonicalFoodId), ["black-coffee"])
        XCTAssertEqual(decoded.nutritionValidation?.status, .approved)

        let meal = Meal(id: UUID(), title: "Black coffee", subtitle: "Test", mealType: "Breakfast", time: .now, energy: 2, carbs: 0, protein: 0, fat: 0, artwork: .neutral, confidence: .estimated, analysis: result)
        let item = ThreadItem(id: UUID(), kind: .meal(meal))
        let day = Day(id: UUID(), date: .now, messages: [item], energyGoal: 2_000, carbohydrateGoal: 180)
        let store = DiaryStore(days: [day])
        XCTAssertEqual(store.day(id: day.id)?.totalEnergy, 2)
        var edited = meal
        edited.energy = 4
        store.update(edited, in: day.id)
        XCTAssertEqual(store.day(id: day.id)?.totalEnergy, 4)
        XCTAssertEqual(store.day(id: day.id)?.meals.count, 1)
    }

    @MainActor
    func testConfirmedDraftReplacesDraftAndAddsMealToDay() {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let result = engine.makeAnalysis(description: "Rajma with rice")
        let draft = MealAnalysisDraft(result: result)
        let day = Day(id: UUID(), date: .now, messages: [ThreadItem(id: UUID(), kind: .mealAnalysis(draft))], energyGoal: 2_000, carbohydrateGoal: 180)
        let store = DiaryStore(days: [day])
        let itemID = day.messages[0].id

        let meal = DiaryMealLoggingService().confirm(draft, replacing: itemID, in: store, dayID: day.id)
        XCTAssertEqual(store.day(id: day.id)?.meals.first?.id, meal.id)
        XCTAssertEqual(store.day(id: day.id)?.messages.count, 1)
    }
}
