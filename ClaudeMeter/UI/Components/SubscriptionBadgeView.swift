//
//  SubscriptionBadgeView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Badge displaying the current subscription plan
struct SubscriptionBadgeView: View {
    let subscriptionType: SubscriptionType

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: subscriptionType.icon)
                .font(.system(size: 12, weight: .semibold))

            Text(subscriptionType.displayName + " Plan")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [subscriptionType.color, subscriptionType.secondaryColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: subscriptionType.color.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

/// Compact inline badge variant
struct SubscriptionBadgeCompact: View {
    let subscriptionType: SubscriptionType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: subscriptionType.icon)
                .font(.system(size: 10, weight: .semibold))

            Text(subscriptionType.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(subscriptionType.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(subscriptionType.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        ForEach(SubscriptionType.allCases) { type in
            HStack {
                SubscriptionBadgeView(subscriptionType: type)
                Spacer()
                SubscriptionBadgeCompact(subscriptionType: type)
            }
        }
    }
    .padding()
    .frame(width: 350)
}
