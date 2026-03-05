//
//  ZphyrUITests.swift
//  ZphyrUITests
//
//  Created by Aristide Cordonnier on 01/03/2026.
//

import XCTest
import ApplicationServices

final class ZphyrUITests: XCTestCase {

    private func requireUIAutomationAuthorization() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("UI automation is not authorized on this machine.")
        }
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        try requireUIAutomationAuthorization()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launch()
            app.terminate()
        }
    }
}
