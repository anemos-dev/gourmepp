//
//  ______UITests.swift
//  ごはん日和UITests
//
//  Created by 木村風葉 on 2026/07/17.
//

import XCTest

final class ______UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testSampleGridFiltersAndDetailNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding", "-seedReleasePreview"]
        app.launch()

        XCTAssertTrue(app.buttons["すべて"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["行った"].exists)
        XCTAssertTrue(app.buttons["行きたい"].exists)
        XCTAssertFalse(app.buttons["気になる"].exists)

        let sampleCard = app.buttons["湯気ラーメン 代々木、行った"]
        XCTAssertTrue(sampleCard.waitForExistence(timeout: 8))
        sampleCard.tap()

        XCTAssertTrue(app.navigationBars["店舗詳細"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["湯気ラーメン 代々木"].exists)
    }

    @MainActor
    func testCreateEditTrashAndRestoreRecord() throws {
        let app = launchApp()

        app.tabBars.buttons["記録する"].tap()
        XCTAssertTrue(app.buttons["enterPlaceManually"].waitForExistence(timeout: 5))
        app.buttons["enterPlaceManually"].tap()

        let nameField = app.textFields["manualPlaceName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Release QA Cafe")
        app.textFields["manualPlaceAddress"].tap()
        app.textFields["manualPlaceAddress"].typeText("東京都渋谷区")
        app.buttons["recordManualPlace"].tap()

        let memoField = app.textFields["recordMemo"]
        XCTAssertTrue(memoField.waitForExistence(timeout: 5))
        memoField.tap()
        memoField.typeText("初回メモ")
        app.buttons["saveRecord"].tap()

        XCTAssertTrue(app.navigationBars["店舗を手入力"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        app.tabBars.buttons["ホーム"].tap()

        let visitedCard = app.buttons["Release QA Cafe、行った"]
        XCTAssertTrue(visitedCard.waitForExistence(timeout: 5))
        visitedCard.tap()
        XCTAssertTrue(app.navigationBars["店舗詳細"].waitForExistence(timeout: 5))

        app.buttons["その他"].tap()
        app.buttons["記録を編集"].tap()
        XCTAssertTrue(app.navigationBars["記録を編集"].waitForExistence(timeout: 5))
        app.buttons["行きたい"].tap()
        app.buttons["saveRecordEdits"].tap()

        XCTAssertTrue(app.navigationBars["店舗詳細"].waitForExistence(timeout: 5))
        app.buttons["その他"].tap()
        app.buttons["ゴミ箱に移動"].tap()
        app.alerts.buttons["移動"].tap()

        app.tabBars.buttons["マイページ"].tap()
        let trash = app.staticTexts["ゴミ箱（1件）"]
        for _ in 0..<6 where !trash.isHittable { app.swipeUp() }
        XCTAssertTrue(trash.isHittable)
        trash.tap()
        XCTAssertTrue(app.navigationBars["ゴミ箱"].waitForExistence(timeout: 5))
        app.buttons["復元"].tap()

        app.tabBars.buttons["ホーム"].tap()
        XCTAssertTrue(app.buttons["Release QA Cafe、行きたい"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProLockedAndUnlockedStates() throws {
        let lockedApp = launchApp()
        lockedApp.tabBars.buttons["マイページ"].tap()
        lockedApp.staticTexts["Proの機能を見る"].tap()
        XCTAssertTrue(lockedApp.buttons["購入を復元"].waitForExistence(timeout: 5))
        lockedApp.terminate()

        let unlockedApp = launchApp(additionalArguments: ["-unlockPro"])
        unlockedApp.tabBars.buttons["マイページ"].tap()
        XCTAssertTrue(unlockedApp.staticTexts["Pro購入済み"].waitForExistence(timeout: 5))
        XCTAssertTrue(unlockedApp.staticTexts["年間ごはんレポート"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            launchApp().terminate()
        }
    }

    @MainActor
    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"] + additionalArguments
        app.launch()
        return app
    }
}
