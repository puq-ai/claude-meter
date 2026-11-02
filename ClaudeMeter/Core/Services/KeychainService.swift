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
    /// The Claude Code CLI's Keychain service. Only ever READ from - `save`/`delete` take an
    /// explicit service and default to the app's own, so nothing here can clobber the CLI.
    private let serviceName = Constants.Keychain.serviceName

    // MARK: - Generic Password Methods

    func save(data: Data, account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Item exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
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

    func read(account: String, service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    func delete(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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
    /// another app's Keychain items via Security framework.
    ///
    /// The subprocess is waited on from a background queue: callers are on the main actor,
    /// and `waitUntilExit()` there both froze the UI and spun the main run loop, letting
    /// other main-actor work re-enter mid-fetch.
    private func readCredentialsViaShell() async throws -> Data {
        let service = serviceName
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try Self.runSecurityFindPassword(service: service) })
            }
        }
    }

    private static func runSecurityFindPassword(service: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        // Never read, so it must not be a pipe that could fill up and block the child.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw KeychainError.unexpectedStatus(errSecNotAvailable)
        }

        // Read output before waiting (prevents deadlock on large output)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        // `security` exits 44 (errSecItemNotFound) when there is no such item. Anything else -
        // a locked keychain, denied access - is a read failure, not "never logged in".
        switch process.terminationStatus {
        case 0: break
        case 44: throw KeychainError.itemNotFound
        default: throw KeychainError.unexpectedStatus(process.terminationStatus)
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
    /// - Returns: nil when the CLI has never stored credentials.
    /// - Throws: `KeychainError` when an item exists but can't be read or parsed - a
    ///   format change in the CLI must not masquerade as "please log in".
    func getCredentials() async throws -> ClaudeCredentials? {
        let data: Data
        do {
            // Use shell command to avoid Keychain password prompt
            data = try await readCredentialsViaShell()
        } catch KeychainError.itemNotFound {
            return nil
        }

        let decoder = JSONDecoder()
        // Wrapped format: { "claudeAiOauth": { ... } }
        if let keychainData = try? decoder.decode(ClaudeKeychainData.self, from: data) {
            return ClaudeCredentials(oauth: keychainData.claudeAiOauth)
        }
        // Bare OAuth object
        if let oauthData = try? decoder.decode(ClaudeOAuthData.self, from: data) {
            return ClaudeCredentials(oauth: oauthData)
        }
        do {
            return try decoder.decode(ClaudeCredentials.self, from: data)
        } catch {
            print("KeychainService: Unrecognised credential format - \(error)")
            throw KeychainError.invalidItemFormat
        }
    }

    /// Check if Claude Code credentials exist in Keychain
    func hasCredentials() async -> Bool {
        do {
            _ = try await readCredentialsViaShell()
            return true
        } catch {
            return false
        }
    }
}

private extension ClaudeCredentials {
    init(oauth: ClaudeOAuthData) {
        self.init(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: Date(timeIntervalSince1970: oauth.expiresAt / 1000), // ms to seconds
            subscriptionType: oauth.subscriptionType ?? Constants.Credentials.defaultSubscriptionType
        )
    }
}
