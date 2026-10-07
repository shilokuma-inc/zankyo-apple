//
//  ZankyoUITests.swift
//  ZankyoUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class ZankyoUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsRootTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["ライブラリ"].waitForExistence(timeout: 5))
    }
}
