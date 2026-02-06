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
    /// Save data to keychain
    /// - Parameters:
    ///   - data: The data to save
    ///   - account: The account identifier
    func save(data: Data, account: String) throws

    /// Read data from keychain
    /// - Parameter account: The account identifier
    /// - Returns: The stored data
    func read(account: String) throws -> Data

    /// Delete data from keychain
    /// - Parameter account: The account identifier
    func delete(account: String) throws

    /// Get Claude credentials from keychain
    /// - Returns: ClaudeCredentials if found
    func getCredentials() throws -> ClaudeCredentials?

    /// Check if Claude Code credentials exist in Keychain
    /// - Returns: True if credentials exist
    func hasCredentials() -> Bool
}
