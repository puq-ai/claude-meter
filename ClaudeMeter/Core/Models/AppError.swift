//
//  AppError.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Unified error types for the application
enum AppError: Error, LocalizedError, Equatable {
    // MARK: - Authentication Errors
    case noCredentials
    case invalidCredentials
    case credentialsExpired
    case authenticationFailed(String)

    // MARK: - Network Errors
    case networkUnavailable
    case connectionTimeout
    case serverUnreachable
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String?)

    // MARK: - Data Errors
    case invalidResponse
    case decodingFailed(String)
    case noData

    // MARK: - Keychain Errors
    case keychainReadFailed
    case keychainWriteFailed
    case keychainItemNotFound

    // MARK: - General Errors
    case unknown(String)
    case cancelled

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Claude Code credentials found. Please log in to Claude Code first."
        case .invalidCredentials:
            return "Invalid credentials. Please re-authenticate with Claude Code."
        case .credentialsExpired:
            return "Your credentials have expired. Please re-authenticate."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"

        case .networkUnavailable:
            return "Network is unavailable. Please check your connection."
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .serverUnreachable:
            return "Unable to reach the server. Please try again later."
        case .rateLimited(let retryAfter):
            if let retry = retryAfter {
                return "Rate limited. Please wait \(Int(retry)) seconds."
            }
            return "Rate limited. Please wait and try again."
        case .serverError(let code, let message):
            if let msg = message {
                return "Server error (\(code)): \(msg)"
            }
            return "Server error: \(code)"

        case .invalidResponse:
            return "Received an invalid response from the server."
        case .decodingFailed(let details):
            return "Failed to process server response: \(details)"
        case .noData:
            return "No data received from the server."

        case .keychainReadFailed:
            return "Failed to read from Keychain."
        case .keychainWriteFailed:
            return "Failed to write to Keychain."
        case .keychainItemNotFound:
            return "Keychain item not found."

        case .unknown(let message):
            return message
        case .cancelled:
            return "Operation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noCredentials, .invalidCredentials, .credentialsExpired:
            return "Run 'claude login' in Terminal to authenticate."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .rateLimited:
            return "The API is rate limited. Wait a moment before trying again."
        case .serverError:
            return "The server may be experiencing issues. Try again later."
        default:
            return nil
        }
    }

    // MARK: - Equatable

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.noCredentials, .noCredentials),
             (.invalidCredentials, .invalidCredentials),
             (.credentialsExpired, .credentialsExpired),
             (.networkUnavailable, .networkUnavailable),
             (.connectionTimeout, .connectionTimeout),
             (.serverUnreachable, .serverUnreachable),
             (.invalidResponse, .invalidResponse),
             (.noData, .noData),
             (.keychainReadFailed, .keychainReadFailed),
             (.keychainWriteFailed, .keychainWriteFailed),
             (.keychainItemNotFound, .keychainItemNotFound),
             (.cancelled, .cancelled):
            return true
        case let (.authenticationFailed(m1), .authenticationFailed(m2)):
            return m1 == m2
        case let (.rateLimited(r1), .rateLimited(r2)):
            return r1 == r2
        case let (.serverError(c1, m1), .serverError(c2, m2)):
            return c1 == c2 && m1 == m2
        case let (.decodingFailed(d1), .decodingFailed(d2)):
            return d1 == d2
        case let (.unknown(m1), .unknown(m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

// MARK: - Error Conversion

extension AppError {
    /// Convert from APIError to AppError
    static func from(_ apiError: APIError) -> AppError {
        switch apiError {
        case .invalidURL:
            return .unknown("Invalid URL configuration")
        case .noData:
            return .noData
        case .decodingError:
            return .decodingFailed("Failed to decode API response")
        case .serverError(let code):
            return .serverError(statusCode: code, message: nil)
        case .unauthorized:
            return .invalidCredentials
        case .rateLimited:
            return .rateLimited(retryAfter: nil)
        case .networkError(let error):
            return .unknown(error.localizedDescription)
        case .maxRetriesExceeded:
            return .serverUnreachable
        case .unknown(let error):
            return .unknown(error.localizedDescription)
        }
    }

    /// Convert from KeychainError to AppError
    static func from(_ keychainError: KeychainError) -> AppError {
        switch keychainError {
        case .itemNotFound:
            return .keychainItemNotFound
        case .duplicateItem, .invalidItemFormat, .unexpectedStatus:
            return .keychainReadFailed
        }
    }
}

// MARK: - Error Severity

extension AppError {
    enum Severity {
        case info
        case warning
        case error
        case critical
    }

    var severity: Severity {
        switch self {
        case .cancelled:
            return .info
        case .rateLimited, .connectionTimeout:
            return .warning
        case .noCredentials, .networkUnavailable, .noData:
            return .error
        case .invalidCredentials, .credentialsExpired, .serverError, .serverUnreachable:
            return .critical
        default:
            return .error
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .rateLimited, .connectionTimeout, .serverUnreachable, .networkUnavailable:
            return true
        case .serverError(let code, _):
            return code >= 500
        default:
            return false
        }
    }
}
