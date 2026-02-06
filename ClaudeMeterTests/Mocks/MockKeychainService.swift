//
//  MockKeychainService.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
@testable import ClaudeMeter

/// Mock keychain service for testing
class MockKeychainService: KeychainServiceProtocol {
    // MARK: - Storage
    private var storage: [String: Data] = [:]

    // MARK: - Call Tracking
    var saveCallCount = 0
    var readCallCount = 0
    var deleteCallCount = 0
    var getCredentialsCallCount = 0
    var hasCredentialsCallCount = 0

    // MARK: - Stubbed Responses
    var stubbedCredentials: ClaudeCredentials?
    var stubbedHasCredentials = false
    var shouldThrowOnSave = false
    var shouldThrowOnRead = false

    // MARK: - KeychainServiceProtocol

    func save(data: Data, account: String) throws {
        saveCallCount += 1

        if shouldThrowOnSave {
            throw KeychainError.unexpectedStatus(-1)
        }

        storage[account] = data
    }

    func read(account: String) throws -> Data {
        readCallCount += 1

        if shouldThrowOnRead {
            throw KeychainError.itemNotFound
        }

        guard let data = storage[account] else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    func delete(account: String) throws {
        deleteCallCount += 1
        storage.removeValue(forKey: account)
    }

    func getCredentials() throws -> ClaudeCredentials? {
        getCredentialsCallCount += 1
        return stubbedCredentials
    }

    func hasCredentials() -> Bool {
        hasCredentialsCallCount += 1
        return stubbedHasCredentials
    }

    // MARK: - Reset

    func reset() {
        storage.removeAll()
        saveCallCount = 0
        readCallCount = 0
        deleteCallCount = 0
        getCredentialsCallCount = 0
        hasCredentialsCallCount = 0
        stubbedCredentials = nil
        stubbedHasCredentials = false
        shouldThrowOnSave = false
        shouldThrowOnRead = false
    }
}
