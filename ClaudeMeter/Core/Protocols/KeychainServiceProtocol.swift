//
//  KeychainServiceProtocol.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Protocol defining the keychain service interface for credential management
protocol KeychainServiceProtocol {
    /// Save data to keychain under an explicit service
    func save(data: Data, account: String, service: String) throws

    /// Read data from keychain under an explicit service
    func read(account: String, service: String) throws -> Data

    /// Delete data from keychain under an explicit service
    func delete(account: String, service: String) throws

    /// Get Claude Code's credentials from the keychain
    /// - Returns: ClaudeCredentials if found
    func getCredentials() throws -> ClaudeCredentials?

    /// Check if Claude Code credentials exist in Keychain
    /// - Returns: True if credentials exist
    func hasCredentials() -> Bool
}

// Swift protocol requirements cannot carry default arguments, so the convenience overloads
// live here. They default to the app's OWN service: nothing this app writes should ever
// land in the Claude Code CLI's item.
extension KeychainServiceProtocol {
    func save(data: Data, account: String) throws {
        try save(data: data, account: account, service: Constants.Keychain.appServiceName)
    }

    func read(account: String) throws -> Data {
        try read(account: account, service: Constants.Keychain.appServiceName)
    }

    func delete(account: String) throws {
        try delete(account: account, service: Constants.Keychain.appServiceName)
    }

    // MARK: - claude.ai web session

    func saveWebSessionKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidItemFormat }
        try save(data: data, account: Constants.Keychain.webSessionAccount)
    }

    func readWebSessionKey() -> String? {
        guard let data = try? read(account: Constants.Keychain.webSessionAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteWebSessionKey() throws {
        try delete(account: Constants.Keychain.webSessionAccount)
    }
}
