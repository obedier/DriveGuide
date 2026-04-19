import XCTest

/// End-to-end journey: launch → Nearby Cities chip → sheet → pick Miami → verify search
/// text is populated. Uses a hard-coded Miami simulator location via scheme launch args.
final class NearbyCitiesJourneyTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNearbyCitiesChipOpensSheetAndFillsSearch() throws {
        let app = XCUIApplication()
        // Disable any splash/onboarding timings we can via env flags and seed
        // a known location so the metro sheet resolves to a deterministic row.
        app.launchArguments += ["-uiTestingMode", "1", "-disableAnimations", "1"]
        app.launchEnvironment["UITEST_SIMULATED_LATITUDE"] = "25.7617"
        app.launchEnvironment["UITEST_SIMULATED_LONGITUDE"] = "-80.1918"
        app.launch()

        // The Explore tab should be the default; locate the Nearby Cities chip.
        let chip = app.buttons["nearbyCitiesChip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "Expected the Nearby Cities chip on the Home screen. " +
                      "If this fails, the search text may be non-empty or a location may already be verified.")

        chip.tap()

        // The sheet title is "Nearby Cities" — wait for it to appear.
        let sheetTitle = app.staticTexts["Nearby Cities"]
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 5))

        // In CI or simulator-without-location the sheet may land in one of:
        //   - .loaded (when simulator location is set)
        //   - .permissionDenied (needs Settings deep-link)
        //   - .locationUnavailable (shows Retry + top-US fallback)
        //   - .loading (still resolving)
        //
        // The fallback list always contains Miami, so we poll for it for 5s.
        let miamiRow = app.buttons["metroRow-Miami"]
        let showed = miamiRow.waitForExistence(timeout: 8)

        if !showed {
            // If the sheet is in permission-denied mode, we stop here — the feature
            // is rendering its recovery UI correctly. XCTSkip ensures CI doesn't
            // turn red for environmental reasons.
            let settingsButton = app.buttons["Open Settings"]
            if settingsButton.exists {
                throw XCTSkip("Simulator location permission was denied; recovery UI rendered.")
            }
            XCTFail("No metro row appeared and no recovery UI visible — unexpected state.")
            return
        }

        miamiRow.tap()

        // After dismissing, the search field should contain "Miami, FL".
        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        let value = searchField.value as? String ?? ""
        XCTAssertTrue(value.contains("Miami"),
                      "Expected searchField value to contain 'Miami' after row tap, got '\(value)'")
    }
}
