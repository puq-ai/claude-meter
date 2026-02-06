//
//  ClaudeMeterUITests.swift
//  ClaudeMeterUITests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest

class ClaudeMeterUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }
    
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Since it's a menu bar app, we might need specific logic to interact with the menu extra
        // For standard UI tests, this might just verify app doesn't crash on launch
    }
}
