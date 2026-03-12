//
//  DebugLogger.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: Category
    let message: String
    let detail: String?

    enum Category: String {
        case request = "REQ"
        case response = "RES"
        case fallback = "FALLBACK"
        case cache = "CACHE"
        case error = "ERR"
        case info = "INFO"

        var icon: String {
            switch self {
            case .request: return "arrow.up.circle"
            case .response: return "arrow.down.circle"
            case .fallback: return "arrow.triangle.2.circlepath"
            case .cache: return "cylinder"
            case .error: return "xmark.circle"
            case .info: return "info.circle"
            }
        }
    }
}

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var entries: [DebugLogEntry] = []
    private let maxEntries = 200

    func log(_ category: DebugLogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        print("[\(category.rawValue)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }
}
