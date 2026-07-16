import XCTest

final class DiafitUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["UITestMode"]
        app.launch()
    }

    func testFreshLaunchIsEmptyAndShowsThreeMetricSummary() throws {
        XCTAssertTrue(app.staticTexts["No meals logged yet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Add food"].exists)
        XCTAssertFalse(app.staticTexts["Yogurt, berries & seeds"].exists)
        XCTAssertFalse(app.staticTexts["Miso salmon plate"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["daily-summary-calories"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["daily-summary-carbohydrates"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["daily-summary-protein"].exists)
    }

    func testMealAtlasOpensAndCloses() throws {
        submitFoodNote("Pasta for dinner")
        XCTAssertTrue(app.staticTexts["Tomato basil pasta"].waitForExistence(timeout: 4))

        // The diary follows the newest conversation moment; reveal its header.
        app.swipeDown()
        app.swipeDown()

        let atlasButton = app.buttons["Open meal atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3))
        atlasButton.tap()

        XCTAssertTrue(app.staticTexts["The day in plates"].waitForExistence(timeout: 2))
        attachScreenshot(named: "meal-atlas")
        let closeButton = app.buttons["Close meal atlas"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()
        XCTAssertFalse(app.staticTexts["The day in plates"].waitForExistence(timeout: 1))
    }

    func testQuickFoodNoteAddsAnAgentMeal() throws {
        submitFoodNote("Pasta for dinner")

        XCTAssertTrue(app.staticTexts["Tomato basil pasta"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["That sounds comforting. I’ve put it in as a generous pasta portion; you can fine-tune it any time."].waitForExistence(timeout: 3))
        attachScreenshot(named: "logged-pasta")
    }

    func testAddingAndDeletingMealUpdatesAllTotalsAndRestoresEmptyState() throws {
        submitFoodNote("Pasta for dinner")

        let savedMeal = app.buttons["Saved meal Tomato basil pasta"]
        XCTAssertTrue(savedMeal.waitForExistence(timeout: 4))
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(metricLabel("daily-summary-calories").contains("682"))
        XCTAssertTrue(metricLabel("daily-summary-carbohydrates").contains("79"))
        XCTAssertTrue(metricLabel("daily-summary-protein").contains("25"))

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(savedMeal.waitForExistence(timeout: 2))
        savedMeal.press(forDuration: 1.1)
        let deleteMeal = app.buttons["Delete meal"]
        XCTAssertTrue(deleteMeal.waitForExistence(timeout: 2))
        deleteMeal.tap()
        app.buttons["Delete"].tap()

        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["No meals logged yet"].waitForExistence(timeout: 3))
        XCTAssertTrue(metricLabel("daily-summary-calories").contains("0"))
        XCTAssertTrue(metricLabel("daily-summary-carbohydrates").contains("0"))
        XCTAssertTrue(metricLabel("daily-summary-protein").contains("0"))
    }

    func testUnrecognisedFoodCreatesReviewInsteadOfGuessing() throws {
        submitFoodNote("Chicken wrap and an apple")

        XCTAssertTrue(app.staticTexts["Let’s identify the plate"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["I don’t want to guess. Add the main dish and I’ll make an editable estimate."].waitForExistence(timeout: 3))
    }

    func testBlackCoffeeCreatesPlausibleEditableReview() throws {
        submitFoodNote("black coffee")

        XCTAssertTrue(app.staticTexts["Black coffee"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["kcal"].exists)
        XCTAssertFalse(app.staticTexts["470"].exists)
        XCTAssertTrue(app.buttons["Confirm estimate"].waitForExistence(timeout: 2))
    }

    func testSproutsWithThreeBoiledEggsShowsComponentsTotalsVisualAndPersists() throws {
        submitFoodNote("sprouts with 3 boiled eggs")

        XCTAssertTrue(app.staticTexts["Mixed sprouts"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Boiled egg"].exists)
        XCTAssertEqual(app.textFields["Boiled egg quantity"].value as? String, "3")
        XCTAssertTrue(app.descendants(matching: .any)["meal-total-kcal"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["meal-total-protein"].exists)
        XCTAssertTrue(app.staticTexts["MEAL VISUAL READY"].exists)

        let caloriesBefore = metricLabel("meal-total-kcal")
        // The review card is taller than the simulator viewport; reveal the
        // editable component row before changing its explicit serving control.
        app.swipeDown()
        app.swipeDown()
        let unitMenu = app.buttons["Change Mixed sprouts serving unit"]
        XCTAssertTrue(unitMenu.exists)
        unitMenu.tap()
        app.buttons["small bowl"].tap()
        XCTAssertNotEqual(metricLabel("meal-total-kcal"), caloriesBefore)

        let confirm = app.buttons["Confirm estimate"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        let saved = app.buttons["Saved meal Mixed sprouts + Boiled egg"]
        XCTAssertTrue(saved.waitForExistence(timeout: 4))
        saved.press(forDuration: 1.1)
        let refine = app.buttons["Refine estimate"]
        XCTAssertTrue(refine.waitForExistence(timeout: 2))
        refine.tap()
        XCTAssertTrue(app.staticTexts["Mixed sprouts"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["MEAL VISUAL READY"].exists)
        attachScreenshot(named: "sprouts-and-three-eggs-review")
    }

    func testOneScoopWheyWithWaterShowsNutritionVisualAndPersists() throws {
        submitFoodNote("one scoop whey protein with water")

        XCTAssertTrue(app.staticTexts["Whey protein"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.textFields["Whey protein quantity"].value as? String, "1")
        XCTAssertTrue(app.descendants(matching: .any)["meal-total-kcal"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["meal-total-protein"].exists)
        XCTAssertTrue(app.staticTexts["MEAL VISUAL READY"].exists)
        XCTAssertFalse(metricLabel("meal-total-kcal").contains("—"))
        XCTAssertFalse(metricLabel("meal-total-protein").contains("—"))

        let confirm = app.buttons["Confirm estimate"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.buttons["Saved meal Whey protein"].waitForExistence(timeout: 4))
        attachScreenshot(named: "whey-water-review")
    }

    func testConfirmedMealSurvivesProcessRelaunch() throws {
        app.terminate()
        app.launchArguments = ["UITestMode", "UITestPersistentDiary"]
        app.launchEnvironment["DIAFIT_UI_TEST_DIARY_ID"] = UUID().uuidString
        app.launch()

        submitFoodNote("one scoop whey protein with water")
        let confirm = app.buttons["Confirm estimate"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        XCTAssertTrue(app.buttons["Saved meal Whey protein"].waitForExistence(timeout: 4))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Saved meal Whey protein"].waitForExistence(timeout: 5))
        attachScreenshot(named: "persisted-meal-after-relaunch")
    }

    func testChaiAndParathaShowsBothComponentsThenUsesNeutralPlaceholder() throws {
        submitFoodNote("chai and paratha")

        XCTAssertTrue(app.staticTexts["Chai"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Paratha"].exists)
        XCTAssertTrue(app.staticTexts["Was the chai sweetened, and approximately how much milk was used?"].exists)
        XCTAssertTrue(app.staticTexts["Was the paratha plain, stuffed or buttered?"].exists)

        app.buttons["Milk + sugar"].tap()
        app.buttons["Plain"].tap()
        let confirm = app.buttons["Confirm estimate"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertFalse(app.buttons["Confirm estimate"].exists)
        XCTAssertFalse(app.staticTexts["Market salad bowl"].exists)
    }

    func testFastingGlucoseCanBeLoggedAndAppearsInDailyThread() throws {
        let logButton = app.buttons["Log glucose"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 3))
        logButton.tap()

        let value = app.textFields["Glucose value"]
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        value.tap()
        value.typeText("96")
        app.buttons["Save glucose"].tap()

        XCTAssertTrue(app.staticTexts["Fasting"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["96 mg/dL"].exists)
    }

    func testPostMealGlucoseEntryKeepsMealAssociationFlowAvailable() throws {
        let logButton = app.buttons["Log glucose"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 3))
        logButton.tap()
        app.buttons["Post-meal"].tap()

        XCTAssertTrue(app.buttons["Save glucose"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Post-meal"].isSelected)
    }

    private func submitFoodNote(_ text: String) {
        let note = app.textFields["Tell me what you ate"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText(text)
        app.swipeDown()
        let send = app.buttons["Send food note"]
        XCTAssertTrue(send.waitForExistence(timeout: 2))
        send.tap()
    }

    private func metricLabel(_ identifier: String) -> String {
        app.descendants(matching: .any)[identifier].label
    }

    func testPhotoReviewFixtureWithUnsupportedComponentStaysUnconfirmed() throws {
        app.terminate()
        app.launchArguments.append("UITestUseFixturePhoto")
        app.launch()

        let photoButton = app.buttons["Add meal photo"]
        XCTAssertTrue(photoButton.waitForExistence(timeout: 3))
        photoButton.tap()

        let fixture = app.buttons["Use review fixture"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 2))
        fixture.tap()

        let review = app.buttons["Create a review"]
        XCTAssertTrue(review.waitForExistence(timeout: 2))
        review.tap()

        XCTAssertTrue(app.staticTexts["A likely reading of this meal"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Dosa"].exists)
        XCTAssertTrue(app.staticTexts["Sambar"].exists)

        app.buttons["1"].tap()
        app.buttons["No / very little"].tap()
        let confirm = app.buttons["Answer to confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)
        attachScreenshot(named: "unsupported-photo-review")
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
