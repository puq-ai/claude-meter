//
//  Credentials.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

struct ClaudeCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let subscriptionType: String     // "pro", "max", "free"

    var isValid: Bool {
        return Date() < expiresAt
    }

    var isExpiringSoon: Bool {
        return expiresAt.timeIntervalSinceNow < Constants.Credentials.expirationWarningThreshold
    }

    var timeUntilExpiration: TimeInterval {
        return expiresAt.timeIntervalSinceNow
    }

    // Custom decoding to handle both Date and TimeInterval formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        subscriptionType = try container.decodeIfPresent(String.self, forKey: .subscriptionType) ?? "pro"

        // Try decoding as Date first, then as TimeInterval
        if let date = try? container.decode(Date.self, forKey: .expiresAt) {
            expiresAt = date
        } else if let timestamp = try? container.decode(TimeInterval.self, forKey: .expiresAt) {
            expiresAt = Date(timeIntervalSince1970: timestamp)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.expiresAt],
                    debugDescription: "Expected Date or TimeInterval for expiresAt"
                )
            )
        }
    }

    // Standard initializer
    init(accessToken: String, refreshToken: String, expiresAt: Date, subscriptionType: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    // Custom encoding to ensure consistent format
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(expiresAt.timeIntervalSince1970, forKey: .expiresAt)
        try container.encode(subscriptionType, forKey: .subscriptionType)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case subscriptionType
    }
}
