//
//  ZphyrUITestsLaunchTests.swift
//  ZphyrUITests
//
//  Created by Aristide Cordonnier on 01/03/2026.
//

import XCTest
import ApplicationServices

final class ZphyrUITestsLaunchTests: XCTestCase {

    private func requireUIAutomationAuthorization() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("UI automation is not authorized on this machine.")
        }
    }

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try requireUIAutomationAuthorization()
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
