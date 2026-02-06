//
//  AboutView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

// MARK: - About View
struct AboutView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        SettingsTabContainer {
            ScrollView {
                VStack(spacing: 16) {
                    // App Logo
                    Image("AppLogo")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Constants.UI.aboutLogoSize, height: Constants.UI.aboutLogoSize)

                    // App Name
                    Text("ClaudeMeter")
                        .font(.title)
                        .fontWeight(.bold)

                    // Version
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.vertical, 4)

                    // Description
                    Text("A macOS menu bar app for monitoring Claude Code usage limits.")
                        .multilineTextAlignment(.center)
                        .font(.body)
                        .foregroundColor(.secondary)

                    Spacer()
                        .frame(height: 16)

                    Spacer()
                        .frame(height: 8)

                    // Copyright
                    Text("© 2026 puq.ai. All rights reserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
        }
    }
}
