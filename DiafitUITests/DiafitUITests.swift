import XCTest

final class DiafitUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testMealAtlasOpensAndCloses() throws {
        // The diary opens at the newest conversation moment; reveal its header.
        app.swipeDown()
        app.swipeDown()

        let atlasButton = app.buttons["Open meal atlas"]
        XCTAssertTrue(atlasButton.waitForExistence(timeout: 3))
        atlasButton.tap()

        XCTAssertTrue(app.staticTexts["Meal atlas"].waitForExistence(timeout: 2))
        attachScreenshot(named: "meal-atlas")
        let closeButton = app.buttons["Close meal atlas"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()
        XCTAssertFalse(app.staticTexts["Meal atlas"].waitForExistence(timeout: 1))
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

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
