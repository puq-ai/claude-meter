//
//  ConnectView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import AppKit

/// Shown when there is nothing to authenticate with. Replaces the old "No Usage Data - click
/// refresh" empty state, which told a user who had never signed in to press a button that
/// could not possibly work.
struct ConnectView: View {
    @ObservedObject var appState: AppState

    @State private var isSigningIn = false
    @State private var didCopyCommand = false
    @State private var pollTask: Task<Void, Never>?

    private static let loginCommand = "claude login"

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "person.badge.key")
                .font(.system(size: 34))
                .foregroundColor(.secondary)

            Text("Connect your account")
                .font(.headline)

            Text("ClaudeMeter reads usage from the Claude Code CLI. Sign in there, or connect a claude.ai session instead.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            VStack(spacing: 8) {
                Button {
                    startWebLogin()
                } label: {
                    Label("Sign in with claude.ai", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigningIn)

                Button {
                    openTerminalWithLoginCommand()
                } label: {
                    Label(didCopyCommand ? "Copied - paste in Terminal" : "Use the Claude Code CLI",
                          systemImage: didCopyCommand ? "checkmark" : "terminal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Opens Terminal and copies `\(Self.loginCommand)` to the clipboard")
            }
            .padding(.horizontal, 24)

            if isSigningIn {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for sign-in…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear(perform: startWatchingForCredentials)
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - claude.ai

    private func startWebLogin() {
        isSigningIn = true
        WebLoginController.shared.present { outcome in
            isSigningIn = false
            guard case .signedIn(let sessionKey, let organizations) = outcome,
                  let organization = organizations.preferredForUsage else { return }
            appState.applyWebSession(sessionKey: sessionKey, organization: organization)
        }
    }

    // MARK: - Claude Code CLI

    /// Copies the command and opens Terminal rather than running it via AppleScript, which
    /// would require Automation permission and an entitlement for a one-line convenience.
    private func openTerminalWithLoginCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.loginCommand, forType: .string)
        didCopyCommand = true

        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The CLI writes its credentials to the Keychain, which the file watcher (it watches
    /// `~/.claude`) cannot see. Poll while this screen is up so signing in elsewhere is
    /// noticed without the user having to come back and press refresh.
    private func startWatchingForCredentials() {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<150 {   // ~5 minutes at 2s
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                if appState.hasCLICredentials {
                    await appState.refresh(reason: "credentials_detected")
                    return
                }
            }
        }
    }
}
