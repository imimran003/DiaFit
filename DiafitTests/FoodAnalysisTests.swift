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

    func testHybridNormaliserAcceptsSpellingAndRegionalVariants() {
        let normaliser = HybridFoodNormalisationService(catalog: catalog)
        XCTAssertEqual(normaliser.normalise("mung sprouts")?.canonicalId, "moong-sprouts")
        XCTAssertEqual(normaliser.normalise("ande")?.canonicalId, "whole-egg")
        XCTAssertEqual(normaliser.normalise("chapati")?.canonicalId, "roti")
    }

    func testMealParseContractContainsNoTrustedNutrition() {
        let item = ParsedFoodItem(originalText: "3 boiled eggs", canonicalSearchName: "chicken egg", quantity: 3, unit: "whole")
        let parse = MealParseResult(detectedItems: [item], unresolvedItems: [], mealDescription: "eggs", clarificationQuestions: [], confidence: 0.95)
        XCTAssertNil(parse.detectedItems.first?.estimatedGrams)
        XCTAssertFalse(BackendFoodUnderstandingService.strictJSONSchema.isEmpty)
    }

    func testCatalogRecipeCalculationSumsVerifiedIngredients() async {
        let service = CatalogRecipeCalculationService(resolver: HybridNutritionResolutionService(catalog: catalog))
        let result = await service.calculate(ingredients: [
            RecipeIngredient(canonicalSearchName: "boiled egg", quantity: 3, unit: "wholeEgg"),
            RecipeIngredient(canonicalSearchName: "mixed sprouts", quantity: 1, unit: "mediumBowl")
        ])
        XCTAssertFalse(result.lookup.values.isEmpty)
        XCTAssertEqual(result.lookup.provenance.kind, .curatedRecipeEstimate)
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

    /// Regression fixture captured from the free-text composer. This deliberately
    /// fails against the alias-only resolver: it must become a component meal,
    /// retain the explicit egg quantity and provide an editable sprouts estimate.
    func testSproutsWithThreeBoiledEggsIsACompleteComponentMeal() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "I had sprouts with 3 boiled eggs")

        XCTAssertEqual(result.detectedItems.count, 2)
        XCTAssertEqual(result.detectedItems.first(where: { $0.canonicalFoodId == "mixed-sprouts" })?.quantity, 1)
        let eggs = try XCTUnwrap(result.detectedItems.first(where: { $0.canonicalFoodId == "boiled-egg" }))
        XCTAssertEqual(eggs.quantity, 3)
        XCTAssertEqual(eggs.servingUnit, .wholeEgg)
        XCTAssertEqual(eggs.preparationMethod, "boiled")
        XCTAssertFalse(eggs.nutrition.isEmpty)
        XCTAssertFalse(result.mealTotals.isEmpty)
        XCTAssertTrue(result.visualRequest?.prompt.contains("exactly three peeled boiled eggs") == true)
    }

    /// A protein shake is a supplement composition, not an unknown drink. The
    /// default estimate remains editable, but it must never fall into an empty
    /// nutrition state when there is enough information for a generic record.
    func testWheyProteinShakeCreatesEditableSupplementDraft() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "whey protein shake")

        let whey = try XCTUnwrap(result.detectedItems.first(where: { $0.canonicalFoodId == "generic-whey-protein" }))
        XCTAssertEqual(whey.quantity, 1)
        XCTAssertEqual(whey.servingUnit, .scoop)
        XCTAssertFalse(whey.nutrition.isEmpty)
        XCTAssertFalse(result.mealTotals.isEmpty)
        XCTAssertTrue(result.clarificationQuestions.contains { $0.question.contains("How many scoops") })
        XCTAssertEqual(result.visualRequest?.state, .waitingForClarification)
    }

    func testEggRecognitionPreservesPluralQuantityAndPreparation() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures: [(String, String, Double, ServingUnit, String?)] = [
            ("1 boiled egg", "boiled-egg", 1, .wholeEgg, "boiled"),
            ("2 boiled eggs", "boiled-egg", 2, .wholeEgg, "boiled"),
            ("three boiled eggs", "boiled-egg", 3, .wholeEgg, "boiled"),
            ("boiled eggs", "boiled-egg", 1, .wholeEgg, "boiled"),
            ("egg whites", "egg-white", 1, .piece, nil),
            ("4 egg whites", "egg-white", 4, .piece, nil),
            ("scrambled eggs", "scrambled-egg", 1, .wholeEgg, "scrambled"),
            ("omelette", "omelette", 1, .piece, nil),
            ("fried egg", "fried-egg", 1, .wholeEgg, "fried")
        ]

        for (input, id, quantity, unit, preparation) in fixtures {
            let item = try XCTUnwrap(engine.makeAnalysis(description: input).detectedItems.first, input)
            XCTAssertEqual(item.canonicalFoodId, id, input)
            XCTAssertEqual(item.quantity, quantity, input)
            XCTAssertEqual(item.servingUnit, unit, input)
            if let preparation { XCTAssertEqual(item.preparationMethod, preparation, input) }
            XCTAssertFalse(item.nutrition.isEmpty, input)
        }
    }

    func testSproutRecognitionProducesUsableEditableNutrition() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures: [(String, String, Double, ServingUnit, String?)] = [
            ("sprouts", "mixed-sprouts", 1, .mediumBowl, nil),
            ("mixed sprouts", "mixed-sprouts", 1, .mediumBowl, nil),
            ("one bowl sprouts", "mixed-sprouts", 1, .mediumBowl, nil),
            ("moong sprouts", "moong-sprouts", 1, .mediumBowl, nil),
            ("cooked sprouts", "mixed-sprouts", 1, .mediumBowl, "cooked"),
            ("sprout salad", "sprout-salad", 1, .mediumBowl, nil)
        ]

        for (input, id, quantity, unit, preparation) in fixtures {
            let item = try XCTUnwrap(engine.makeAnalysis(description: input).detectedItems.first, input)
            XCTAssertEqual(item.canonicalFoodId, id, input)
            XCTAssertEqual(item.quantity, quantity, input)
            XCTAssertEqual(item.servingUnit, unit, input)
            if let preparation { XCTAssertEqual(item.preparationMethod, preparation, input) }
            XCTAssertFalse(item.nutrition.isEmpty, input)
        }
    }

    func testQuantityParserSupportsFractionsPairAndScoops() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures: [(String, Double, ServingUnit)] = [
            ("half scoop whey with water", 0.5, .scoop),
            ("one and a half scoop whey with water", 1.5, .scoop),
            ("two scoops protein powder with water", 2, .scoop),
            ("pair boiled eggs", 2, .wholeEgg),
            ("one bowl sprouts", 1, .mediumBowl)
        ]
        for (input, expectedQuantity, expectedUnit) in fixtures {
            let first = try XCTUnwrap(engine.makeAnalysis(description: input).detectedItems.first, input)
            XCTAssertEqual(first.quantity, expectedQuantity, accuracy: 0.001, input)
            XCTAssertEqual(first.servingUnit, expectedUnit, input)
        }
    }

    func testCompoundMealsRemainDecomposedAcrossConnectors() {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures: [(String, Set<String>)] = [
            ("sprouts with three boiled eggs", ["mixed-sprouts", "boiled-egg"]),
            ("three eggs with sprouts", ["whole-egg", "mixed-sprouts"]),
            ("sprouts and egg whites", ["mixed-sprouts", "egg-white"]),
            ("whey shake and banana", ["generic-whey-protein", "banana"]),
            ("three boiled eggs with toast", ["boiled-egg", "toast"]),
            ("sprouts, eggs and black coffee", ["mixed-sprouts", "whole-egg", "black-coffee"]),
            ("protein shake with oats and milk", ["generic-whey-protein", "oats"])
        ]
        for (input, expectedIDs) in fixtures {
            XCTAssertEqual(Set(engine.makeAnalysis(description: input).detectedItems.map(\.canonicalFoodId)), expectedIDs, input)
        }
    }

    /// Regression from baseline diagnostics: a quantity belongs to the food
    /// phrase it modifies. It must not cross `with`/`and` and become the next
    /// component's quantity or serving unit.
    func testCompoundQuantitiesStayWithTheirFood() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)

        let eggsAndSprouts = engine.makeAnalysis(description: "three eggs with sprouts")
        let eggs = try XCTUnwrap(eggsAndSprouts.detectedItems.first { $0.canonicalFoodId == "whole-egg" })
        let sprouts = try XCTUnwrap(eggsAndSprouts.detectedItems.first { $0.canonicalFoodId == "mixed-sprouts" })
        XCTAssertEqual(eggs.quantity, 3)
        XCTAssertEqual(eggs.servingUnit, .wholeEgg)
        XCTAssertEqual(sprouts.quantity, 1)
        XCTAssertEqual(sprouts.servingUnit, .mediumBowl)

        let wheyAndBanana = engine.makeAnalysis(description: "two scoops whey and banana")
        let whey = try XCTUnwrap(wheyAndBanana.detectedItems.first { $0.canonicalFoodId == "generic-whey-protein" })
        let banana = try XCTUnwrap(wheyAndBanana.detectedItems.first { $0.canonicalFoodId == "banana" })
        XCTAssertEqual(whey.quantity, 2)
        XCTAssertEqual(whey.servingUnit, .scoop)
        XCTAssertEqual(banana.quantity, 1)
        XCTAssertEqual(banana.servingUnit, .piece)
    }

    func testExtendedMealConnectorsKeepQuantitiesWithTheFollowingFood() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures = [
            "sprouts served with 3 boiled eggs",
            "sprouts along with three boiled eggs",
            "sprouts together with 2 eggs",
            "sprouts accompanied by 4 eggs"
        ]

        for input in fixtures {
            let result = engine.makeAnalysis(description: input)
            let eggs = try XCTUnwrap(result.detectedItems.first { $0.category == .egg }, input)
            let sprouts = try XCTUnwrap(result.detectedItems.first { $0.category == .sprouts }, input)
            XCTAssertEqual(eggs.quantity, input.contains("4") ? 4 : input.contains("2") ? 2 : 3, input)
            XCTAssertEqual(eggs.servingUnit, .wholeEgg, input)
            XCTAssertEqual(sprouts.quantity, 1, input)
            XCTAssertEqual(sprouts.servingUnit, .mediumBowl, input)
        }
    }

    func testPunctuationDoesNotBreakFoodAliasesAndDecimalQuantitiesRemainExact() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let meal = engine.makeAnalysis(description: "I had 1.5 scoops whey protein with water.")
        let whey = try XCTUnwrap(meal.detectedItems.first { $0.category == .supplement })

        XCTAssertEqual(whey.quantity, 1.5, accuracy: 0.001)
        XCTAssertEqual(whey.servingUnit, .scoop)
        XCTAssertEqual(whey.supplementProfile?.base, .water)
        XCTAssertFalse(whey.nutrition.isEmpty)
    }

    func testCompoundPreparationsStayWithTheirFood() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let result = engine.makeAnalysis(description: "fried eggs with raw sprouts")
        let eggs = try XCTUnwrap(result.detectedItems.first { $0.canonicalFoodId == "fried-egg" })
        let sprouts = try XCTUnwrap(result.detectedItems.first { $0.canonicalFoodId == "mixed-sprouts" })

        XCTAssertEqual(eggs.preparationMethod, "fried")
        XCTAssertEqual(sprouts.preparationMethod, "raw")
    }

    func testWheyVariantsAndBasesUseFirstClassSupplementRecords() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let fixtures: [(String, String, Double, ServingUnit, SupplementBase)] = [
            ("one scoop whey with water", "generic-whey-protein", 1, .scoop, .water),
            ("two scoops whey with water", "generic-whey-protein", 2, .scoop, .water),
            ("one scoop whey with milk", "generic-whey-protein", 1, .scoop, .milk),
            ("whey isolate shake", "generic-whey-isolate", 1, .scoop, .unspecified),
            ("whey concentrate shake", "generic-whey-concentrate", 1, .scoop, .unspecified),
            ("chocolate whey protein", "generic-whey-protein", 1, .scoop, .unspecified),
            ("ready-to-drink protein shake", "ready-to-drink-protein-shake", 1, .serving, .unspecified)
        ]
        for (input, id, quantity, unit, base) in fixtures {
            let item = try XCTUnwrap(engine.makeAnalysis(description: input).detectedItems.first, input)
            XCTAssertEqual(item.canonicalFoodId, id, input)
            XCTAssertEqual(item.quantity, quantity, input)
            XCTAssertEqual(item.servingUnit, unit, input)
            XCTAssertEqual(item.supplementProfile?.base, base, input)
            XCTAssertFalse(item.nutrition.isEmpty, input)
        }
    }

    func testWheyWaterAddsNoCaloriesAndMilkAddsItsOwnNutrition() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let water = engine.makeAnalysis(description: "one scoop whey protein with water")
        let milk = engine.makeAnalysis(description: "one scoop whey protein with milk")
        let waterItem = try XCTUnwrap(water.detectedItems.first)
        let milkItem = try XCTUnwrap(milk.detectedItems.first)

        XCTAssertEqual(waterItem.supplementProfile?.base, .water)
        XCTAssertEqual(milkItem.supplementProfile?.base, .milk)
        XCTAssertEqual(water.mealTotals.caloriesKcal ?? -1, waterItem.nutrition.caloriesKcal ?? -2, accuracy: 0.001)
        XCTAssertGreaterThan(milk.mealTotals.caloriesKcal ?? 0, water.mealTotals.caloriesKcal ?? .infinity)
        XCTAssertGreaterThan(milk.mealTotals.proteinGrams ?? 0, water.mealTotals.proteinGrams ?? .infinity)
        XCTAssertTrue(water.visualRequest?.prompt.contains("water") == true)
        XCTAssertFalse(water.visualRequest?.prompt.contains("banana") ?? true)
        XCTAssertFalse(water.visualRequest?.prompt.contains("milk") ?? true)
    }

    func testQuantitySensitiveVisualPromptAndCacheNeverReuseWrongMealImage() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let threeEggs = engine.makeAnalysis(description: "sprouts with 3 boiled eggs")
        let twoEggs = engine.makeAnalysis(description: "sprouts with 2 boiled eggs")
        let prompt = try XCTUnwrap(threeEggs.visualRequest?.prompt)

        XCTAssertTrue(prompt.contains("mixed sprouts"))
        XCTAssertTrue(prompt.contains("exactly three peeled boiled eggs"))
        XCTAssertTrue(prompt.contains("No unrelated foods"))
        XCTAssertTrue(prompt.contains("No extra eggs"))
        XCTAssertTrue(prompt.contains("No salad ingredients"))
        XCTAssertNotEqual(threeEggs.visualRequest?.cacheKey, twoEggs.visualRequest?.cacheKey)
        XCTAssertNotEqual(threeEggs.visualRequest?.requestID, twoEggs.visualRequest?.requestID)
    }

    func testProviderIndependentIntegrationProducesUIReadyResult() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "protein shake with banana and milk")
        let whey = try XCTUnwrap(result.detectedItems.first(where: { $0.category == .supplement }))

        XCTAssertEqual(Set(result.detectedItems.map(\.canonicalFoodId)), Set(["generic-whey-protein", "banana"]))
        XCTAssertEqual(whey.supplementProfile?.base, .milk)
        XCTAssertFalse(result.mealTotals.isEmpty)
        XCTAssertEqual(result.nutritionValidation?.isApproved, true)
        XCTAssertEqual(result.visualRequest?.state, .queued)
        XCTAssertNotNil(result.visualRequest?.cacheKey)
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

    func testWaterUsesDeterministicHydrationFastPath() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "500 ml water")
        let water = try XCTUnwrap(result.detectedItems.first)

        XCTAssertEqual(water.canonicalFoodId, "water")
        XCTAssertEqual(water.quantity, 500, accuracy: 0.001)
        XCTAssertEqual(water.servingUnit, .millilitres)
        XCTAssertEqual(water.nutrition.caloriesKcal ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(water.nutrition.carbohydrateGrams ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(result.clarificationQuestions.isEmpty)
        XCTAssertTrue(result.nutritionValidation?.isApproved == true)
    }

    func testKadhiChawalDecomposesTransliteratedCompoundMeal() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "I had kadhi chaawal")
        XCTAssertEqual(Set(result.detectedItems.map(\.canonicalFoodId)), Set(["kadhi", "steamed-rice"]))
        XCTAssertFalse(result.detectedItems.contains { $0.canonicalFoodId == "kadhi" && $0.nutrition.isEmpty })
        XCTAssertFalse(result.detectedItems.contains { $0.canonicalFoodId == "steamed-rice" && $0.nutrition.isEmpty })
        XCTAssertFalse(result.mealTotals.isEmpty)
    }

    func testHydrationAliasesAndVolumesRemainDeterministic() throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        for input in ["water", "paani", "one glass water", "2 litres water"] {
            let result = engine.makeAnalysis(description: input)
            let water = try XCTUnwrap(result.detectedItems.first, input)
            XCTAssertEqual(water.canonicalFoodId, "water", input)
            XCTAssertFalse(water.nutrition.isEmpty, input)
            XCTAssertTrue(result.nutritionValidation?.isApproved == true, input)
        }
        XCTAssertEqual(engine.makeAnalysis(description: "2 litres water").detectedItems.first?.quantity, 2_000)
    }

    func testFoodResolutionRouterUsesLocalCanonicalRouteBeforeAI() async throws {
        let router = DefaultFoodResolutionRouter(catalog: catalog)
        let result = await router.resolve(text: "kadhi chaawal")

        XCTAssertEqual(Set(result.items.compactMap { $0.canonical?.food.canonicalId }), Set(["kadhi", "steamed-rice"]))
        XCTAssertTrue(result.items.allSatisfy { $0.interpretationRoute == .exactLocal || $0.interpretationRoute == .localAlias || $0.interpretationRoute == .localTransliteration })
        XCTAssertFalse(result.unresolvedTerms.isEmpty == false && result.items.isEmpty)
        XCTAssertFalse(result.items.contains { $0.nutrition.lookup.values.isEmpty })
    }

    func testFoodResolutionRouterUsesStructuredAIOnlyAfterLocalMiss() async throws {
        let parsed = MealParseResult(
            detectedItems: [ParsedFoodItem(originalText: "dragon fruit", canonicalSearchName: "banana", quantity: 1, unit: "piece", confidence: 0.88)],
            unresolvedItems: [], mealDescription: "dragon fruit", clarificationQuestions: [], confidence: 0.88
        )
        let router = DefaultFoodResolutionRouter(
            catalog: catalog,
            understanding: StubMealUnderstanding(result: parsed),
            nutrition: HybridNutritionResolutionService(catalog: catalog)
        )
        let result = await router.resolve(text: "dragon fruit")

        XCTAssertEqual(result.items.first?.interpretationRoute, .openAI)
        XCTAssertEqual(result.items.first?.canonical?.food.canonicalId, "banana")
        XCTAssertFalse(result.items.first?.nutrition.lookup.values.isEmpty ?? true)
    }

    func testNamedLocalCandidateWithBlankNutritionTriggersStructuredAIAndReturnsUsableNutrition() async throws {
        let counter = ParseCounter()
        let parsed = MealParseResult(
            detectedItems: [ParsedFoodItem(originalText: "khichdi", canonicalSearchName: "khichdi", quantity: 1, unit: "mediumBowl", confidence: 0.92)],
            unresolvedItems: [], mealDescription: "khichdi", clarificationQuestions: [], confidence: 0.92
        )
        let router = DefaultFoodResolutionRouter(
            catalog: catalog,
            understanding: CountingMealUnderstanding(result: parsed, counter: counter),
            nutrition: HybridNutritionResolutionService(catalog: catalog)
        )

        let result = await router.resolve(text: "khichdi")

        let parseCount = await counter.value
        XCTAssertEqual(parseCount, 1, "An incomplete local record must invoke structured meal interpretation")
        XCTAssertEqual(result.items.first?.canonical?.food.canonicalId, "khichdi")
        XCTAssertFalse(result.items.first?.nutrition.lookup.values.isEmpty ?? true)
        XCTAssertNotEqual(result.items.first?.nutrition.lookup.provenance.kind, .unavailable)
        XCTAssertEqual(result.state, .readyForReview)
    }

    func testCompletenessGateRejectsRecognisedFoodWithMissingNutrition() {
        let food = catalog.food(canonicalID: "khichdi")!
        let parsed = ParsedFoodItem(originalText: "khichdi", canonicalSearchName: "Khichdi", quantity: 1, unit: "mediumBowl")
        let match = CanonicalFoodMatch(food: food, matchedAlias: "khichdi", confidence: 0.95, source: "local-canonical-catalog")
        let item = FoodResolutionItem(
            parsedItem: parsed,
            canonical: match,
            nutrition: NutritionResolution(lookup: NutritionLookup(values: .unavailable, provenance: .unavailable), sourceRecordID: nil, servingAmount: 1, servingUnit: "mediumBowl", estimatedGrams: 250, assumptions: [], verified: false),
            interpretationRoute: .exactLocal,
            nutritionRoute: .unavailable
        )

        let report = FoodResolutionCompletenessEvaluator().evaluate(item)
        XCTAssertFalse(report.isComplete)
        XCTAssertTrue(report.missingRequirements.contains("calories"))
        XCTAssertTrue(report.missingRequirements.contains("nutrition source"))
    }

    func testCoordinatorProducesEditableNutritionForKhichdiInsteadOfBlankDashes() async throws {
        let parsed = MealParseResult(
            detectedItems: [ParsedFoodItem(originalText: "khichdi", canonicalSearchName: "khichdi", quantity: 1, unit: "mediumBowl", confidence: 0.92)],
            unresolvedItems: [], mealDescription: "khichdi", clarificationQuestions: [], confidence: 0.92
        )
        let router = DefaultFoodResolutionRouter(
            catalog: catalog,
            understanding: StubMealUnderstanding(result: parsed),
            nutrition: HybridNutritionResolutionService(catalog: catalog)
        )
        let result = await HybridMealAnalysisCoordinator(router: router).analyse(text: "khichdi")

        XCTAssertFalse(result.detectedItems.isEmpty)
        XCTAssertFalse(result.mealTotals.isEmpty)
        XCTAssertNotEqual(result.nutritionProvenance.kind, .unavailable)
        XCTAssertTrue(result.nutritionValidation?.isApproved == true)
    }

    func testArharDaalWithChaawalDoesNotStopAtIncompleteLocalDaalRecord() async throws {
        let result = await DefaultFoodResolutionRouter(catalog: catalog).resolve(text: "arhar daal with chaawal")

        XCTAssertEqual(Set(result.items.compactMap { $0.canonical?.food.canonicalId }), Set(["toor-dal", "steamed-rice"]))
        XCTAssertTrue(result.items.allSatisfy { !$0.nutrition.lookup.values.isEmpty })
        XCTAssertNotEqual(result.items.first?.nutrition.lookup.provenance.kind, .unavailable)
        XCTAssertEqual(result.state, .readyForReview)
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

    func testVisualIdentityFollowsTheStructuredRequestAcrossRenders() throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "sprouts with 3 boiled eggs")
        let request = try XCTUnwrap(result.visualRequest)
        let factory = MealVisualIdentityFactory()

        let first = factory.make(mealID: request.mealID, result: result, artwork: .neutral)
        let second = factory.make(mealID: request.mealID, result: result, artwork: .neutral)

        XCTAssertEqual(first.requestID, request.requestID)
        XCTAssertEqual(second.requestID, request.requestID)
        XCTAssertEqual(first.cacheKey, request.cacheKey)
        XCTAssertEqual(second.cacheKey, request.cacheKey)
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

    @MainActor
    func testUnavailableVisualProviderProducesTruthfulRecoverableFallback() async throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "sprouts with 3 boiled eggs")
        let draft = MealAnalysisDraft(result: result)
        let itemID = UUID()
        let day = Day(
            id: UUID(), date: .now,
            messages: [ThreadItem(id: itemID, kind: .mealAnalysis(draft))],
            energyGoal: 2_000, carbohydrateGoal: 180
        )
        let store = DiaryStore(days: [day])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-visual-fallback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = MealVisualGenerationService(
            generator: UnavailableMealVisualGenerator(),
            assets: MealVisualAssetStore(directory: directory, appliesFileProtection: false),
            ledger: MealVisualRequestLedger()
        )

        await service.prepare(draft: draft, itemID: itemID, in: store, dayID: day.id)

        guard case .mealAnalysis(let updated)? = store.day(id: day.id)?.messages.first?.kind else {
            return XCTFail("Expected an updated review draft")
        }
        XCTAssertEqual(updated.result.visualRequest?.state, .deterministicFallback)
        XCTAssertNil(updated.result.generatedVisualAsset)
        XCTAssertTrue(updated.result.visualRequest?.failureReason?.contains("unavailable") == true)
    }

    @MainActor
    func testGeneratedVisualAttachesToConfirmedMatchingMealAndPersistsReference() async throws {
        let result = LocalMealAnalysisEngine(catalog: catalog)
            .makeAnalysis(description: "sprouts with 3 boiled eggs")
        let draft = MealAnalysisDraft(result: result)
        let itemID = UUID()
        let day = Day(
            id: UUID(), date: .now,
            messages: [ThreadItem(id: itemID, kind: .mealAnalysis(draft))],
            energyGoal: 2_000, carbohydrateGoal: 180
        )
        let store = DiaryStore(days: [day])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-visual-success-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = MealVisualGenerationService(
            generator: TestMealVisualGenerator(mode: .success),
            assets: MealVisualAssetStore(directory: directory, appliesFileProtection: false),
            ledger: MealVisualRequestLedger()
        )

        // Confirmation can happen before a remote image returns. The service
        // must then update the saved meal, never an obsolete draft object.
        _ = DiaryMealLoggingService().confirm(draft, replacing: itemID, in: store, dayID: day.id)
        await service.prepare(draft: draft, itemID: itemID, in: store, dayID: day.id)

        let meal = try XCTUnwrap(store.day(id: day.id)?.meals.first)
        XCTAssertEqual(meal.analysis?.visualRequest?.state, .ready)
        XCTAssertEqual(meal.visualIdentity?.source, .generatedEditorial)
        let fileName = try XCTUnwrap(meal.visualIdentity?.assetFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path))
        let restored = try JSONDecoder().decode(Meal.self, from: JSONEncoder().encode(meal))
        XCTAssertEqual(restored.visualIdentity?.assetFileName, fileName)
        XCTAssertEqual(restored.analysis?.generatedVisualAsset?.cacheKey, result.visualRequest?.cacheKey)
    }

    @MainActor
    func testVisualRetryForAnEditedMealUpdatesOnlyTheVisualRequestUntilConfirmation() async throws {
        let engine = LocalMealAnalysisEngine(catalog: catalog)
        let original = engine.makeAnalysis(description: "sprouts with 2 boiled eggs")
        let draft = MealAnalysisDraft(result: original)
        let itemID = UUID()
        let day = Day(
            id: UUID(), date: .now,
            messages: [ThreadItem(id: itemID, kind: .mealAnalysis(draft))],
            energyGoal: 2_000, carbohydrateGoal: 180
        )
        let store = DiaryStore(days: [day])
        let meal = DiaryMealLoggingService().confirm(draft, replacing: itemID, in: store, dayID: day.id)
        let originalEnergy = meal.energy

        var editedResult = try XCTUnwrap(meal.analysis)
        let eggIndex = try XCTUnwrap(editedResult.detectedItems.firstIndex { $0.category == .egg })
        editedResult.detectedItems[eggIndex].quantity = 3
        editedResult.visualRequest = MealVisualRequestBuilder().make(
            mealID: editedResult.analysisId,
            items: editedResult.detectedItems,
            clarificationQuestions: editedResult.clarificationQuestions
        )
        let editedDraft = MealAnalysisDraft(result: editedResult)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-visual-edit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = MealVisualGenerationService(
            generator: UnavailableMealVisualGenerator(),
            assets: MealVisualAssetStore(directory: directory, appliesFileProtection: false),
            ledger: MealVisualRequestLedger()
        )

        await service.prepare(draft: editedDraft, itemID: itemID, in: store, dayID: day.id)

        let updated = try XCTUnwrap(store.day(id: day.id)?.meals.first)
        XCTAssertEqual(updated.id, meal.id)
        XCTAssertEqual(updated.energy, originalEnergy)
        XCTAssertEqual(updated.analysis?.visualRequest?.state, .deterministicFallback)
        // The edited nutrition draft remains local until the user confirms;
        // only the visual request is allowed to advance during a retry.
        XCTAssertEqual(updated.analysis?.detectedItems.first { $0.category == .egg }?.quantity, 2)
        XCTAssertTrue(updated.analysis?.visualRequest?.quantitySignature.contains { $0.contains(":3.0:") } == true)
    }

    @MainActor
    func testMismatchedVisualResponseIsRejectedWithoutWritingAnAsset() async throws {
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "black coffee")
        let draft = MealAnalysisDraft(result: result)
        let itemID = UUID()
        let day = Day(
            id: UUID(), date: .now,
            messages: [ThreadItem(id: itemID, kind: .mealAnalysis(draft))],
            energyGoal: 2_000, carbohydrateGoal: 180
        )
        let store = DiaryStore(days: [day])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-visual-mismatch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = MealVisualGenerationService(
            generator: TestMealVisualGenerator(mode: .mismatchedMeal),
            assets: MealVisualAssetStore(directory: directory, appliesFileProtection: false),
            ledger: MealVisualRequestLedger()
        )

        await service.prepare(draft: draft, itemID: itemID, in: store, dayID: day.id)

        guard case .mealAnalysis(let updated)? = store.day(id: day.id)?.messages.first?.kind else {
            return XCTFail("Expected an updated review draft")
        }
        XCTAssertEqual(updated.result.visualRequest?.state, .failed)
        XCTAssertNil(updated.result.generatedVisualAsset)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
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

    @MainActor
    func testConfirmedDraftSavesCanonicalFoodMemoryForFutureRouting() async throws {
        let memory = InMemoryUserFoodMemoryRepository()
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "black coffee")
        let draft = MealAnalysisDraft(result: result)
        let day = Day(id: UUID(), date: .now, messages: [ThreadItem(id: UUID(), kind: .mealAnalysis(draft))], energyGoal: 2_000, carbohydrateGoal: 180)
        let store = DiaryStore(days: [day])

        _ = DiaryMealLoggingService(userFoodMemory: memory).confirm(draft, replacing: day.messages[0].id, in: store, dayID: day.id)
        for _ in 0..<10 { await Task.yield() }
        let matches = await memory.rankedMatches(for: "black coffee")

        XCTAssertEqual(matches.first?.canonicalFoodID, "black-coffee")
        XCTAssertEqual(matches.first?.servingUnit, ServingUnit.cup.rawValue)
    }

    func testDiaryPersistsEditsAndDeletionAcrossStoreReloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-diary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileDiaryPersistence(
            fileURL: directory.appendingPathComponent("diary.json"),
            appliesFileProtection: false
        )
        let day = Day(id: UUID(), date: .now, messages: [], energyGoal: 2_000, carbohydrateGoal: 180)
        let meal = Meal(
            id: UUID(), title: "Black coffee", subtitle: "Curated", mealType: "Drink", time: .now,
            energy: 2, carbs: 0, protein: 0, fat: 0, artwork: .neutral, confidence: .estimated
        )

        let firstStore = DiaryStore(seedDays: [day], persistence: persistence)
        firstStore.append(ThreadItem(id: UUID(), kind: .meal(meal)), to: day.id)

        let reloaded = DiaryStore(seedDays: [], persistence: persistence)
        let persistedMeal = try XCTUnwrap(reloaded.day(id: day.id)?.meals.first)
        XCTAssertEqual(persistedMeal.id, meal.id)
        XCTAssertEqual(persistedMeal.energy, meal.energy)
        XCTAssertEqual(
            persistedMeal.time.timeIntervalSince1970,
            meal.time.timeIntervalSince1970,
            accuracy: 0.001
        )

        var edited = meal
        edited.energy = 4
        reloaded.update(edited, in: day.id)
        let afterEdit = DiaryStore(seedDays: [], persistence: persistence)
        XCTAssertEqual(afterEdit.day(id: day.id)?.totalEnergy, 4)
        XCTAssertEqual(afterEdit.day(id: day.id)?.meals.count, 1)

        afterEdit.removeMeal(id: meal.id, from: day.id)
        let afterDelete = DiaryStore(seedDays: [], persistence: persistence)
        XCTAssertEqual(afterDelete.day(id: day.id)?.totalEnergy, 0)
        XCTAssertTrue(afterDelete.day(id: day.id)?.meals.isEmpty == true)
    }

    func testDiaryArchiveDropsTransientPhotoBytesAndRejectsFutureSchemas() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("diafit-diary-privacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("diary.json")
        let persistence = FileDiaryPersistence(fileURL: fileURL, appliesFileProtection: false)
        let result = LocalMealAnalysisEngine(catalog: catalog).makeAnalysis(description: "black coffee")
        let draft = MealAnalysisDraft(result: result, transientImageData: Data([0x01, 0x02, 0x03]))
        let day = Day(
            id: UUID(), date: .now,
            messages: [ThreadItem(id: UUID(), kind: .mealAnalysis(draft))],
            energyGoal: 2_000, carbohydrateGoal: 180
        )

        _ = DiaryStore(seedDays: [day], persistence: persistence)
        let restored = DiaryStore(seedDays: [], persistence: persistence)
        guard case .mealAnalysis(let restoredDraft)? = restored.day(id: day.id)?.messages.first?.kind else {
            return XCTFail("Expected a restored analysis draft")
        }
        XCTAssertNil(restoredDraft.transientImageData)
        XCTAssertEqual(restoredDraft.result.analysisId, result.analysisId)

        let futureArchive = Data("{\"schemaVersion\":999}".utf8)
        try futureArchive.write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try persistence.load()) { error in
            XCTAssertEqual(
                error as? DiaryPersistenceError,
                .unsupportedSchema(found: 999, current: DiaryArchive.currentVersion)
            )
        }
    }

    func testFailedPersistenceNeverPretendsMutationWasSaved() {
        let day = Day(id: UUID(), date: .now, messages: [], energyGoal: 2_000, carbohydrateGoal: 180)
        let store = DiaryStore(seedDays: [day], persistence: AlwaysFailingDiaryPersistence())

        XCTAssertNotNil(store.persistenceIssue)
        store.append(ThreadItem(id: UUID(), kind: .person(text: "black coffee")), to: day.id)
        XCTAssertTrue(store.day(id: day.id)?.messages.isEmpty == true)
        store.retryPersistence()
        XCTAssertNotNil(store.persistenceIssue)
    }
}

private struct StubMealUnderstanding: FoodUnderstandingService {
    let result: MealParseResult

    func parse(text: String, image: PreparedFoodImage?) async throws -> MealParseResult {
        result
    }
}

private actor ParseCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct CountingMealUnderstanding: FoodUnderstandingService {
    let result: MealParseResult
    let counter: ParseCounter

    func parse(text: String, image: PreparedFoodImage?) async throws -> MealParseResult {
        await counter.increment()
        return result
    }
}

private struct AlwaysFailingDiaryPersistence: DiaryPersisting {
    struct Failure: Error {}

    func load() throws -> DiaryArchive? { nil }
    func save(_ archive: DiaryArchive) throws { throw Failure() }
}

private struct TestMealVisualGenerator: MealVisualGenerating {
    enum Mode: Sendable { case success, mismatchedMeal }

    let mode: Mode
    let isConfigured = true

    func generate(_ request: MealVisualRequest) async throws -> GeneratedMealVisual {
        // Valid 1×1 transparent PNG. Core tests validate association and cache
        // behavior without depending on a live image model.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL5WQAAAABJRU5ErkJggg==")!
        return GeneratedMealVisual(
            mealID: mode == .success ? request.mealID : UUID(),
            requestID: request.requestID,
            cacheKey: request.cacheKey,
            mimeType: "image/png",
            data: png
        )
    }
}
