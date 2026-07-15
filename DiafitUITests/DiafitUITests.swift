import XCTest

final class DiafitUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["UITestMode"]
        app.launch()
    }

    func testMealAtlasOpensAndCloses() throws {
        // The diary opens at the newest conversation moment; reveal its header.
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
        let quickNote = app.buttons["Pasta for dinner"]
        XCTAssertTrue(quickNote.waitForExistence(timeout: 3))
        quickNote.tap()

        let send = app.buttons["Send food note"]
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(app.staticTexts["Tomato basil pasta"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["That sounds comforting. I’ve put it in as a generous pasta portion; you can fine-tune it any time."].waitForExistence(timeout: 3))
        attachScreenshot(named: "logged-pasta")
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
