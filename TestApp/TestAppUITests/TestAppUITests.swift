import XCTest

final class TestAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsResultAndFetchButton() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["testFetchKey"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testClearCacheUpdatesResultValue() throws {
        let app = XCUIApplication()
        app.launch()

        let clearButton = app.buttons["clearCachedKey"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let resultElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Test result"))
            .firstMatch

        for _ in 0..<6 where !resultElement.exists {
            app.swipeUp()
        }

        XCTAssertTrue(resultElement.waitForExistence(timeout: 5))
        guard let value = resultElement.value as? String else {
            XCTFail("Expected result element to expose an accessibility value")
            return
        }
        XCTAssertTrue(value.contains("Cache cleared"))
    }
}
