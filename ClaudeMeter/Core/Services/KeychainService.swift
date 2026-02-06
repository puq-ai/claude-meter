//
//  KeychainService.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Security

enum KeychainError: Error, Equatable {
    case itemNotFound
    case duplicateItem
    case invalidItemFormat
    case unexpectedStatus(OSStatus)
}

// MARK: - Claude Code Keychain Data Structures

/// Wrapper struct for Claude Code's OAuth JSON structure in Keychain
struct ClaudeKeychainData: Codable {
    let claudeAiOauth: ClaudeOAuthData

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }
}

/// OAuth data structure stored by Claude Code
struct ClaudeOAuthData: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval  // Unix timestamp
    let subscriptionType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
        case expiresAt = "expiresAt"
        case subscriptionType = "subscriptionType"
    }
}

class KeychainService: KeychainServiceProtocol {
    // Claude Code uses this service name for storing OAuth credentials
    private let serviceName = Constants.Keychain.serviceName

    // MARK: - Generic Password Methods

    func save(data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func read(account: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainError.invalidItemFormat }

        return data
    }

    /// Read without specifying account - finds the first item for the service
    func readFirstItem() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else { throw KeychainError.itemNotFound }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw KeychainError.invalidItemFormat }

        return data
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
             throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Shell-based Keychain Access

    /// Read credentials using security CLI (no password prompt)
    /// This avoids the macOS Keychain password dialog that appears when accessing
    /// another app's Keychain items via Security framework
    private func readCredentialsViaShell() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw KeychainError.itemNotFound
        }

        // Read output before waiting (prevents deadlock on large output)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw KeychainError.itemNotFound
        }

        guard !outputData.isEmpty else {
            throw KeychainError.itemNotFound
        }

        // Remove trailing newline if present
        if let string = String(data: outputData, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.data(using: .utf8) ?? outputData
        }
        return outputData
    }

    // MARK: - Claude Code Credential Helper

    /// Tries to find credentials stored by Claude Code CLI
    /// Claude Code stores credentials in JSON format with claudeAiOauth wrapper
    func getCredentials() throws -> ClaudeCredentials? {
        do {
            // Use shell command to avoid Keychain password prompt
            let data = try readCredentialsViaShell()

            // First try to decode as ClaudeKeychainData (wrapped format)
            if let keychainData = try? JSONDecoder().decode(ClaudeKeychainData.self, from: data) {
                let oauth = keychainData.claudeAiOauth
                return ClaudeCredentials(
                    accessToken: oauth.accessToken,
                    refreshToken: oauth.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000), // ms to seconds
                    subscriptionType: oauth.subscriptionType ?? Constants.Credentials.defaultSubscriptionType
                )
            }

            // Fallback: try to decode as direct ClaudeOAuthData
            if let oauthData = try? JSONDecoder().decode(ClaudeOAuthData.self, from: data) {
                return ClaudeCredentials(
                    accessToken: oauthData.accessToken,
                    refreshToken: oauthData.refreshToken,
                    expiresAt: Date(timeIntervalSince1970: oauthData.expiresAt / 1000), // ms to seconds
                    subscriptionType: oauthData.subscriptionType ?? Constants.Credentials.defaultSubscriptionType
                )
            }

            // Final fallback: try direct ClaudeCredentials decode
            let credentials = try JSONDecoder().decode(ClaudeCredentials.self, from: data)
            return credentials

        } catch KeychainError.itemNotFound {
            return nil
        } catch {
            print("KeychainService: Error reading credentials - \(error)")
            return nil
        }
    }

    /// Check if Claude Code credentials exist in Keychain
    func hasCredentials() -> Bool {
        do {
            _ = try readCredentialsViaShell()
            return true
        } catch {
            return false
        }
    }
}
