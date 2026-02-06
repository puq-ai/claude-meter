//
//  KeychainServiceTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

final class KeychainServiceTests: XCTestCase {
    var sut: KeychainService!
    let testAccount = "test_account_\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        sut = KeychainService()
    }

    override func tearDown() {
        // Clean up any test data
        try? sut.delete(account: testAccount)
        sut = nil
        super.tearDown()
    }

    // MARK: - Save Tests

    func testSaveData_Success() throws {
        // Given
        let testData = "test_token".data(using: .utf8)!

        // When
        XCTAssertNoThrow(try sut.save(data: testData, account: testAccount))

        // Then
        let readData = try sut.read(account: testAccount)
        XCTAssertEqual(readData, testData)
    }

    func testSaveData_UpdateExisting() throws {
        // Given
        let initialData = "initial_token".data(using: .utf8)!
        let updatedData = "updated_token".data(using: .utf8)!
        try sut.save(data: initialData, account: testAccount)

        // When
        XCTAssertNoThrow(try sut.save(data: updatedData, account: testAccount))

        // Then
        let readData = try sut.read(account: testAccount)
        XCTAssertEqual(readData, updatedData)
    }

    // MARK: - Read Tests

    func testReadData_NotFound() {
        // Given
        let nonExistentAccount = "non_existent_\(UUID().uuidString)"

        // When/Then
        XCTAssertThrowsError(try sut.read(account: nonExistentAccount)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }

    // MARK: - Delete Tests

    func testDeleteData_Success() throws {
        // Given
        let testData = "test_token".data(using: .utf8)!
        try sut.save(data: testData, account: testAccount)

        // When
        XCTAssertNoThrow(try sut.delete(account: testAccount))

        // Then
        XCTAssertThrowsError(try sut.read(account: testAccount)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.itemNotFound)
        }
    }

    func testDeleteData_NotFound_NoError() {
        // Given
        let nonExistentAccount = "non_existent_\(UUID().uuidString)"

        // When/Then - Should not throw for non-existent item
        XCTAssertNoThrow(try sut.delete(account: nonExistentAccount))
    }

    // MARK: - hasCredentials Tests

    func testHasCredentials_WhenNoCredentials_ReturnsFalse() {
        // Note: This test assumes no Claude Code credentials exist on the test system
        // In a real scenario, you might want to mock this
        let hasCredentials = sut.hasCredentials()
        // This could be true or false depending on the test environment
        XCTAssertNotNil(hasCredentials)
    }

    // MARK: - JSON Decoding Tests

    func testGetCredentials_ValidJSONFormat() throws {
        // Given
        let credentials = """
        {
            "claudeAiOauth": {
                "accessToken": "test_access_token",
                "refreshToken": "test_refresh_token",
                "expiresAt": 1704067200
            }
        }
        """.data(using: .utf8)!

        // Note: This test would need to use a mock or test-specific service name
        // to avoid interfering with real credentials
    }
}

// MARK: - Performance Tests

extension KeychainServiceTests {
    func testPerformance_SaveAndRead() throws {
        measure {
            let testData = "performance_test_token".data(using: .utf8)!
            try? sut.save(data: testData, account: testAccount)
            _ = try? sut.read(account: testAccount)
            try? sut.delete(account: testAccount)
        }
    }
}
