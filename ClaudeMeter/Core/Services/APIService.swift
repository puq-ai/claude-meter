//
//  APIService.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(statusCode: Int)
    case unauthorized // 401
    case rateLimited(retryAfter: TimeInterval?)  // 429
    case networkError(Error)
    case maxRetriesExceeded(lastError: Error?)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unauthorized:
            return "Unauthorized - check credentials"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited - retry after \(Int(seconds))s"
            }
            return "Rate limited - please wait"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .maxRetriesExceeded(let lastError):
            if let lastError = lastError {
                return "Maximum retries exceeded. Last error: \(lastError.localizedDescription)"
            }
            return "Maximum retries exceeded"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Retry Configuration
struct RetryConfiguration {
    var maxRetries: Int = Constants.Retry.maxRetries
    var initialDelay: TimeInterval = Constants.Retry.initialDelay
    var maxDelay: TimeInterval = Constants.Retry.maxDelay
    var multiplier: Double = Constants.Retry.multiplier

    /// Calculate delay for a given retry attempt (0-indexed)
    func delay(for attempt: Int) -> TimeInterval {
        let delay = initialDelay * pow(multiplier, Double(attempt))
        return min(delay, maxDelay)
    }
}

class APIService: APIServiceProtocol {
    private let baseURL = Constants.API.baseURL
    private let session: URLSession
    private let retryConfig: RetryConfiguration

    init(session: URLSession? = nil, retryConfig: RetryConfiguration = RetryConfiguration()) {
        if let session = session {
            self.session = session
        } else {
            // Configure URLSession with reasonable timeouts
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Constants.API.requestTimeout
            config.timeoutIntervalForResource = Constants.API.resourceTimeout
            self.session = URLSession(configuration: config)
        }
        self.retryConfig = retryConfig
    }

    // MARK: - Endpoints
    enum Endpoint {
        case usage

        var path: String {
            switch self {
            case .usage: return Constants.API.usageEndpoint
            }
        }
    }

    // MARK: - Methods

    /// Fetch usage data without retry
    func fetchUsage(token: String) async throws -> UsageData {
        guard let url = URL(string: baseURL)?.appendingPathComponent(Endpoint.usage.path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers(token: token)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            let debugPath = "/tmp/claudemeter_debug.txt"
            let entry = "[\(Date())] Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)\n\(jsonString)\n---\n"
            if let existing = try? String(contentsOfFile: debugPath, encoding: .utf8) {
                try? (existing + entry).write(toFile: debugPath, atomically: true, encoding: .utf8)
            } else {
                try? entry.write(toFile: debugPath, atomically: true, encoding: .utf8)
            }
        }
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                // The API returns ISO 8601 dates with fractional seconds
                // (e.g. "2026-02-19T07:00:00.125129+00:00") which the built-in
                // .iso8601 strategy does NOT support. Use a custom formatter.
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    if let date = isoFormatter.date(from: dateString) {
                        return date
                    }
                    // Fallback: try without fractional seconds
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    if let date = fallbackFormatter.date(from: dateString) {
                        return date
                    }
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
                }
                return try decoder.decode(UsageData.self, from: data)
            } catch {
                print("APIService: Decoding error: \(error)")
                throw APIError.decodingError
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Fetch usage data with automatic retry and exponential backoff
    func fetchUsageWithRetry(token: String) async throws -> UsageData {
        var lastError: Error = APIError.unknown(NSError(domain: "Unknown", code: -1))

        for attempt in 0..<retryConfig.maxRetries {
            do {
                return try await fetchUsage(token: token)
            } catch let error as APIError {
                lastError = error

                switch error {
                case .rateLimited:
                    // NEVER retry on 429 - each retry extends the rate limit window
                    throw error

                case .serverError(let code) where code >= 500:
                    // 5xx: Wait longer before retry
                    let delay = max(retryConfig.delay(for: attempt), Constants.Retry.serverErrorMinDelay)
                    print("APIService: Server error \(code), waiting \(delay)s before retry \(attempt + 1)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                case .unauthorized:
                    // Don't retry auth errors
                    throw error

                case .networkError:
                    // Network errors: short delay and retry
                    let delay = retryConfig.delay(for: attempt)
                    print("APIService: Network error, waiting \(delay)s before retry \(attempt + 1)")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                default:
                    // Other errors: don't retry
                    throw error
                }
            } catch {
                // URLSession errors (network issues)
                lastError = APIError.networkError(error)
                let delay = retryConfig.delay(for: attempt)
                print("APIService: Request failed, waiting \(delay)s before retry \(attempt + 1)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw APIError.maxRetriesExceeded(lastError: lastError)
    }

    func validateToken(_ token: String) async -> Bool {
        do {
            _ = try await fetchUsage(token: token)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Web API Fallback

    func fetchUsageFromWeb(sessionKey: String, organizationId: String) async throws -> (UsageData, String?) {
        let path = String(format: Constants.API.webUsageEndpoint, organizationId)
        guard let url = URL(string: Constants.API.webBaseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(Constants.API.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            let debugPath = "/tmp/claudemeter_debug.txt"
            let entry = "[\(Date())] [WEB] Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)\n\(jsonString)\n---\n"
            if let existing = try? String(contentsOfFile: debugPath, encoding: .utf8) {
                try? (existing + entry).write(toFile: debugPath, atomically: true, encoding: .utf8)
            } else {
                try? entry.write(toFile: debugPath, atomically: true, encoding: .utf8)
            }
        }
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)
                    if let date = isoFormatter.date(from: dateString) {
                        return date
                    }
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    if let date = fallbackFormatter.date(from: dateString) {
                        return date
                    }
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
                }
                let decoded = try decoder.decode(UsageData.self, from: data)

                // Extract refreshed sessionKey from set-cookie header
                let refreshedSessionKey: String? = {
                    guard let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
                    let components = setCookie.components(separatedBy: ";")
                    guard let keyValue = components.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sessionKey=") }) else { return nil }
                    return keyValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "sessionKey=", with: "")
                }()

                return (decoded, refreshedSessionKey)
            } catch {
                print("APIService: Web API decoding error - \(error)")
                throw APIError.decodingError
            }
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Headers
    private func headers(token: String) -> [String: String] {
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": Constants.API.userAgent,
            "anthropic-beta": Constants.API.anthropicBeta,
            "Accept": Constants.API.acceptType,
            "Content-Type": Constants.API.contentType
        ]
    }
}

// MARK: - Async Extension for easier use
extension APIService {
    /// Convenience method that automatically uses retry
    func getUsage(token: String, withRetry: Bool = true) async throws -> UsageData {
        if withRetry {
            return try await fetchUsageWithRetry(token: token)
        } else {
            return try await fetchUsage(token: token)
        }
    }
}
