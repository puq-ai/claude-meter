//
//  FileWatcherService.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import CoreServices

/// Watches file system directories for changes using FSEvents API
class FileWatcherService {
    private let fileManager = FileManager.default

    // Paths to watch for Claude Code configuration changes
    private let watchPaths: [String]

    // FSEvents stream
    private var eventStream: FSEventStreamRef?
    private var onChange: (() -> Void)?

    // Retained reference for FSEvents callback safety
    private var retainedSelf: Unmanaged<FileWatcherService>?

    // Debounce timer to avoid rapid-fire callbacks
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = Constants.FileWatcher.debounceInterval

    init() {
        // Claude Code configuration paths
        self.watchPaths = Constants.FileWatcher.configPaths.map {
            NSString(string: $0).expandingTildeInPath
        }
    }

    // MARK: - Public Methods

    /// Start watching for file changes
    /// - Parameter onChange: Callback invoked when changes are detected
    func startWatching(onChange: @escaping () -> Void) {
        self.onChange = onChange

        // Filter to existing paths only
        let existingPaths = watchPaths.filter { fileManager.fileExists(atPath: $0) }

        guard !existingPaths.isEmpty else {
            print("FileWatcherService: No Claude config directories found")
            return
        }

        let pathsToWatch = existingPaths as CFArray

        // Retain self for the callback to prevent crash if deallocated
        retainedSelf = Unmanaged.passRetained(self)

        // Context for callback
        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf?.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create FSEvents stream
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Constants.FileWatcher.fsEventsLatency,
            flags
        )

        guard let stream = eventStream else {
            print("FileWatcherService: Failed to create FSEvents stream")
            return
        }

        // Schedule stream on run loop
        FSEventStreamScheduleWithRunLoop(
            stream,
            CFRunLoopGetMain(),
            CFRunLoopMode.defaultMode.rawValue
        )

        // Start the stream
        if !FSEventStreamStart(stream) {
            print("FileWatcherService: Failed to start FSEvents stream")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
            return
        }

        print("FileWatcherService: Started watching \(existingPaths)")
    }

    /// Stop watching for file changes
    func stopWatching() {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard let stream = eventStream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil

        // Release the retained reference
        retainedSelf?.release()
        retainedSelf = nil

        print("FileWatcherService: Stopped watching")
    }

    // MARK: - Private Methods

    fileprivate func handleFileChange() {
        // Ensure timer is scheduled on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Debounce rapid changes
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                self?.onChange?()
            }
        }
    }

    deinit {
        stopWatching()
    }
}

// MARK: - FSEvents Callback

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }

    let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()

    // Get the paths that changed
    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
        return
    }

    // Check if any relevant files changed
    let relevantExtensions = Constants.FileWatcher.relevantExtensions
    let relevantFiles = Constants.FileWatcher.relevantFiles

    var hasRelevantChange = false

    for i in 0..<numEvents {
        let path = paths[i]
        let flags = eventFlags[i]

        // Skip if it's just a root change notification
        if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
            continue
        }

        // Check if it's a relevant file
        let fileName = (path as NSString).lastPathComponent.lowercased()
        let fileExtension = (path as NSString).pathExtension.lowercased()

        if relevantExtensions.contains(fileExtension) ||
           relevantFiles.contains(where: { fileName.contains($0) }) {
            hasRelevantChange = true
            break
        }
    }

    if hasRelevantChange {
        watcher.handleFileChange()
    }
}

// MARK: - Convenience Extension
extension FileWatcherService {
    /// Check if Claude Code config directories exist
    var hasConfigDirectories: Bool {
        return watchPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    /// Get the primary config path
    var primaryConfigPath: String? {
        return watchPaths.first { fileManager.fileExists(atPath: $0) }
    }
}
