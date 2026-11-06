//
//  DryLineUITests.swift
//  DryLineUITests
//
//  Drives the real app in the simulator. No LiDAR there, so these cover the
//  manual-entry path, settings, saved rooms and the results screen.
//

import XCTest

final class DryLineUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func launch() {
        app = XCUIApplication()
        app.launch()
    }

    // MARK: Helpers

    @MainActor
    func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    @MainActor
    func anything(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// The manual-entry number fields, in screen order:
    /// length, width, ceiling height, breakage, doors, windows, door area, window area.
    @MainActor
    var numberFields: XCUIElementQuery {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Enter here"))
    }

    @MainActor
    func goTo(_ tab: String) {
        let item = app.tabBars.buttons[tab]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(tab) tab")
        item.tap()
    }

    @MainActor
    func openRoomDimensions() {
        goTo("Scan")
        if !app.buttons["Use these dimensions"].exists {
            button(containing: "Room dimensions").tap()
        }
        XCTAssertTrue(app.buttons["Use these dimensions"].waitForExistence(timeout: 3))
    }

    @MainActor
    func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(existing.count, 12)))
        field.typeText(text)
    }

    @MainActor
    func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"]
        if done.exists { done.tap() } else if app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap() }
    }

    @MainActor
    func enterRoom(length: String, width: String, height: String) {
        openRoomDimensions()
        XCTAssertGreaterThanOrEqual(numberFields.count, 3)
        replace(numberFields.element(boundBy: 0), with: length)
        replace(numberFields.element(boundBy: 1), with: width)
        replace(numberFields.element(boundBy: 2), with: height)
        dismissKeyboard()
        app.buttons["Use these dimensions"].tap()
    }

    // MARK: Tests

    @MainActor
    func testLaunchShowsTheMainScreen() {
        launch()
        XCTAssertTrue(app.staticTexts["Scan room"].waitForExistence(timeout: 5))
        for tab in ["Scan", "Materials", "Setup", "Saved"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "\(tab) tab")
        }
    }

    @MainActor
    func testManualRoomProducesAMaterialsList() {
        launch()
        enterRoom(length: "4", width: "3", height: "2.4")

        // The dimensions card folds away once used, showing a one-line summary.
        XCTAssertFalse(app.buttons["Use these dimensions"].exists)
        XCTAssertTrue(button(containing: "4 × 3 × 2.4").exists)
        // A shortcut to the results appears on the Scan tab.
        button(containing: "View materials").tap()

        XCTAssertTrue(button(containing: "Copy quote").waitForExistence(timeout: 5), "results appear")
        XCTAssertTrue(anything(containing: "Plasterboard").exists)
        XCTAssertTrue(anything(containing: "Drywall screws").exists)
        XCTAssertTrue(button(containing: "PDF").exists)
        XCTAssertTrue(button(containing: "CSV").exists)
    }

    @MainActor
    func testZeroAndBlankDimensionsAreIgnoredNotCrashed() {
        launch()
        enterRoom(length: "0", width: "3", height: "2.4")
        XCTAssertEqual(app.state, .runningForeground)

        // Blank height.
        openRoomDimensions()
        replace(numberFields.element(boundBy: 2), with: "")
        dismissKeyboard()
        app.buttons["Use these dimensions"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testHugeTypoDoesNotCrash() {
        launch()
        enterRoom(length: "99999999", width: "3", height: "2.4")
        XCTAssertEqual(app.state, .runningForeground)
        goTo("Materials")
        // The absurd walls are skipped and flagged.
        XCTAssertTrue(anything(containing: "Size looks wrong").waitForExistence(timeout: 5))
    }

    @MainActor
    func testCopyQuoteGivesFeedback() {
        launch()
        enterRoom(length: "4", width: "3", height: "2.4")
        goTo("Materials")
        let copy = button(containing: "Copy quote")
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(button(containing: "Copied").waitForExistence(timeout: 2))
    }

    @MainActor
    func testBoardSetupOpensAndLayersSwitch() {
        launch()
        goTo("Setup")
        XCTAssertTrue(app.staticTexts["Board setup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Single layer"].exists)
        app.buttons["Double layer"].tap()
        app.buttons["Single layer"].tap()   // put the setting back
        XCTAssertTrue(app.buttons["Soffit"].exists, "stair boarding options are on Setup")
    }

    @MainActor
    func testSavedRoomsOpensAndCloses() {
        launch()
        goTo("Saved")
        XCTAssertTrue(app.staticTexts["Saved rooms"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Close"].exists, "no Close button on a tab")
        goTo("Scan")
        XCTAssertTrue(app.staticTexts["Scan room"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFloorPlanOpensFromSavedRooms() {
        launch()
        // Make sure there is at least one saved room with an outline.
        enterRoom(length: "4", width: "3", height: "2.4")
        let save = button(containing: "Save walls to")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        button(containing: "Save as new room").tap()

        goTo("Saved")
        XCTAssertTrue(app.staticTexts["Saved rooms"].waitForExistence(timeout: 3))
        button(containing: "Select all").tap()
        let plan = button(containing: "Floor plan")
        XCTAssertTrue(plan.waitForExistence(timeout: 3))
        plan.tap()
        XCTAssertTrue(app.staticTexts["Floor plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(anything(containing: "Total floor area").exists)
        XCTAssertTrue(button(containing: "Share PDF").exists)
        app.buttons["Close"].firstMatch.tap()
    }

    @MainActor
    func testSaveWallsSheetOpensFromAManualRoom() {
        launch()
        enterRoom(length: "4", width: "3", height: "2.4")
        let save = button(containing: "Save walls to")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["Save walls"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Kitchen"].exists, "quick-pick names are shown")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testEveryButtonIsBigEnoughToTap() {
        launch()
        enterRoom(length: "4", width: "3", height: "2.4")
        goTo("Materials")
        XCTAssertTrue(button(containing: "Copy quote").waitForExistence(timeout: 5))
        // Apple's minimum touch target is 44 × 44 pt. (Tab bar items are the system's own.)
        let tabs = Set(["Scan", "Materials", "Setup", "Saved"])
        let small = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && !tabs.contains($0.label) }
            .filter { $0.frame.height < 44 && !$0.label.isEmpty }
            .map { "\($0.label) (\(Int($0.frame.height))pt)" }
        XCTAssertTrue(small.isEmpty, "Buttons under 44pt: \(small)")
    }

    @MainActor
    func testMaterialsTabWithNoRoomPointsBackToScan() {
        launch()
        goTo("Materials")
        let back = button(containing: "Go to Scan")
        if back.exists {           // only when no room is loaded
            back.tap()
            XCTAssertTrue(app.staticTexts["Scan room"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
