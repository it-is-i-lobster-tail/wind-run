import XCTest

@MainActor
final class HistorySearchUITests: XCTestCase {
    private func launch(feedback: Bool = false, holdInterpretation: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-historyDemo", "-searchUITests", "-workoutSearchFeedbackEnabled", feedback ? "YES" : "NO"]
        if feedback { app.launchArguments.append("-workoutSearchRulesOnly") }
        if holdInterpretation { app.launchArguments.append("-holdSearchInterpretation") }
        app.launch()
        return app
    }

    func testAmbiguousCityAndRemovingItsFilter() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("runs in Portland")
        let maine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Portland' AND (label CONTAINS[c] 'ME' OR label CONTAINS[c] 'Maine')")).firstMatch
        XCTAssertTrue(maine.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No matching workouts"].exists)
        maine.tap()
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Remove' AND label CONTAINS[c] 'Portland'")).firstMatch
        XCTAssertTrue(chip.exists)
        XCTAssertTrue(app.buttons["workoutSearchResult"].firstMatch.label.contains("Portland, ME"))
        chip.tap()
        XCTAssertFalse(chip.exists)
        XCTAssertTrue(app.buttons["workoutSearchResult"].firstMatch.exists)
    }

    func testColoradoRunWithOnlyMaineAndOregonHistory() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Colorado run")
        let message = app.staticTexts["No matching workouts"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your recorded workout history has no matches for this search."].exists)
        XCTAssertFalse(app.buttons["No match is right"].exists)
        XCTAssertFalse(app.buttons["workoutSearchResult"].firstMatch.exists)
        field.buttons.firstMatch.tap()
        field.typeText("Oregon run")
        XCTAssertTrue(app.buttons["workoutSearchResult"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
    }

    func testOptedInTesterCanLabelBothKindsOfEmptySearch() {
        let app = launch(feedback: true)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Colorado run\n")
        let correct = app.buttons["No match is right"]
        XCTAssertTrue(correct.waitForExistence(timeout: 5))
        correct.tap()
        XCTAssertTrue(app.staticTexts["Feedback saved"].waitForExistence(timeout: 5))
        field.tap()
        field.buttons.firstMatch.tap()
        field.typeText("Alaska run\n")
        app.buttons["I expected a workout"].tap()
        let workout = app.buttons["feedbackWorkout"].firstMatch
        XCTAssertTrue(workout.waitForExistence(timeout: 5))
        workout.tap()
        XCTAssertTrue(app.staticTexts["Feedback saved"].waitForExistence(timeout: 5))
    }

    func testEditWhileInterpretationIsPending() {
        let app = launch(holdInterpretation: true)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Colorado run\n")
        XCTAssertTrue(app.descendants(matching: .any)["Interpreting search…"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["No matching workouts"].exists)
        field.tap()
        field.buttons.firstMatch.tap()
        field.typeText("last week")
        let lastWeek = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Remove' AND label CONTAINS[c] 'last week'")).firstMatch
        XCTAssertTrue(lastWeek.waitForExistence(timeout: 5))
        let stale = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Remove' AND label CONTAINS[c] 'interval'")).firstMatch
        XCTAssertFalse(stale.waitForExistence(timeout: 5))
        XCTAssertTrue(lastWeek.exists)
    }
}
