//
//  String+Extensions.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

extension String {
    /// Check if string is empty or contains only whitespace
    var isBlank: Bool {
        return self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Truncate string to specified length with ellipsis
    func truncated(to length: Int, addEllipsis: Bool = true) -> String {
        if self.count <= length {
            return self
        }
        let truncated = String(self.prefix(length))
        return addEllipsis ? truncated + "..." : truncated
    }

    /// Convert camelCase to Title Case
    var titleCased: String {
        return self
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    /// Convert to snake_case
    var snakeCased: String {
        let pattern = "([a-z0-9])([A-Z])"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: self.count)
        return regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "$1_$2")
            .lowercased() ?? self.lowercased()
    }

    /// Convert to camelCase
    var camelCased: String {
        let words = self.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let first = words.first?.lowercased() ?? ""
        let rest = words.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    /// Extract numbers from string
    var extractedNumbers: String {
        return self.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }

    /// Check if string contains only digits
    var isNumeric: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }

    /// Safe subscript access
    subscript(safe index: Int) -> Character? {
        guard index >= 0 && index < self.count else { return nil }
        return self[self.index(self.startIndex, offsetBy: index)]
    }

    /// Safe range subscript
    subscript(safe range: Range<Int>) -> String? {
        guard range.lowerBound >= 0,
              range.upperBound <= self.count else { return nil }
        let start = self.index(self.startIndex, offsetBy: range.lowerBound)
        let end = self.index(self.startIndex, offsetBy: range.upperBound)
        return String(self[start..<end])
    }

    /// Mask sensitive data (e.g., tokens)
    func masked(visiblePrefix: Int = 4, visibleSuffix: Int = 4) -> String {
        guard self.count > visiblePrefix + visibleSuffix else {
            return String(repeating: "*", count: self.count)
        }

        let prefix = String(self.prefix(visiblePrefix))
        let suffix = String(self.suffix(visibleSuffix))
        let masked = String(repeating: "*", count: self.count - visiblePrefix - visibleSuffix)

        return prefix + masked + suffix
    }

    /// Format as percentage display
    static func percentage(_ value: Double, decimals: Int = 0) -> String {
        return String(format: "%.\(decimals)f%%", value)
    }

    /// Localized string helper
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        return String(format: NSLocalizedString(self, comment: ""), arguments: arguments)
    }
}

// MARK: - Optional String Extensions

extension Optional where Wrapped == String {
    /// Returns true if nil or empty
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }

    /// Returns true if nil, empty, or blank
    var isNilOrBlank: Bool {
        return self?.isBlank ?? true
    }

    /// Returns the string or a default value
    func orDefault(_ defaultValue: String) -> String {
        return self ?? defaultValue
    }
}
