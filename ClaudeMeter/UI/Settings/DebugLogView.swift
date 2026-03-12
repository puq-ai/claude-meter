//
//  DebugLogView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct DebugLogView: View {
    @ObservedObject private var logger = DebugLogger.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(logger.entries.count) entries")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Copy All") {
                    copyAllLogs()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Button("Clear") {
                    logger.clear()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal)
            .padding(.bottom, 6)

            // Log entries
            if logger.entries.isEmpty {
                Spacer()
                Text("No log entries yet.\nRefresh to generate logs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logger.entries) { entry in
                                logEntryRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal)
                        .textSelection(.enabled)
                        .background(ScrollBarHider())
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: logger.entries.count) { _ in
                        if let last = logger.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func logEntryRow(_ entry: DebugLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.category.icon)
                    .font(.system(size: 9))
                    .foregroundColor(colorFor(entry.category))
                    .frame(width: 12)

                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(entry.category.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(colorFor(entry.category))
                    .frame(width: 52, alignment: .leading)

                Text(entry.message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            if let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 16)
            }
        }
        .padding(.vertical, 2)
    }

    private func colorFor(_ category: DebugLogEntry.Category) -> Color {
        switch category {
        case .request: return .blue
        case .response: return .green
        case .fallback: return .orange
        case .cache: return .purple
        case .error: return .red
        case .info: return .secondary
        }
    }

    private func copyAllLogs() {
        let text = logger.entries.map { entry in
            let time = Self.timeFormatter.string(from: entry.timestamp)
            var line = "[\(time)] [\(entry.category.rawValue)] \(entry.message)"
            if let detail = entry.detail {
                line += "\n  \(detail)"
            }
            return line
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
