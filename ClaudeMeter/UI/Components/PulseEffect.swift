//
//  PulseEffect.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Pulse animation effect for alerts
struct PulseEffect: ViewModifier {
    let isActive: Bool
    let color: Color

    @State private var animating: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(animating ? 1.5 : 1.0)
                    .opacity(animating ? 0 : 0.8)
                    .animation(
                        isActive ?
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false) :
                            .default,
                        value: animating
                    )
            )
            .onChange(of: isActive) { _, newValue in
                animating = newValue
            }
            .onAppear {
                if isActive {
                    animating = true
                }
            }
    }
}

/// Glow effect for critical states
struct GlowEffect: ViewModifier {
    let isActive: Bool
    let color: Color

    @State private var glowing: Bool = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: isActive ? color.opacity(glowing ? 0.8 : 0.3) : .clear,
                radius: isActive ? (glowing ? 10 : 5) : 0
            )
            .animation(
                isActive ?
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                    .default,
                value: glowing
            )
            .onChange(of: isActive) { _, newValue in
                glowing = newValue
            }
            .onAppear {
                if isActive {
                    glowing = true
                }
            }
    }
}

/// Shake effect for errors
struct ShakeEffect: ViewModifier {
    let isActive: Bool
    @State private var shakeOffset: CGFloat = 0
    @State private var shakeWorkItems: [DispatchWorkItem] = []

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    shake()
                }
            }
            .onDisappear {
                cancelShakeAnimation()
            }
    }

    private func cancelShakeAnimation() {
        for item in shakeWorkItems {
            item.cancel()
        }
        shakeWorkItems.removeAll()
    }

    private func shake() {
        // Cancel any ongoing shake animation
        cancelShakeAnimation()

        let offsets: [(offset: CGFloat, delay: Double)] = [
            (5, 0),
            (-5, 0.05),
            (3, 0.1),
            (-3, 0.15),
            (0, 0.2)
        ]

        for (offset, delay) in offsets {
            let workItem = DispatchWorkItem { [self] in
                withAnimation(.linear(duration: 0.05)) {
                    shakeOffset = offset
                }
            }
            shakeWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }
}

// MARK: - View Extensions

extension View {
    func pulseEffect(isActive: Bool, color: Color = .red) -> some View {
        modifier(PulseEffect(isActive: isActive, color: color))
    }

    func glowEffect(isActive: Bool, color: Color = .red) -> some View {
        modifier(GlowEffect(isActive: isActive, color: color))
    }

    func shakeEffect(isActive: Bool) -> some View {
        modifier(ShakeEffect(isActive: isActive))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        Circle()
            .fill(Color.red)
            .frame(width: 50, height: 50)
            .pulseEffect(isActive: true, color: .red)

        Text("Critical!")
            .font(.title)
            .foregroundColor(.red)
            .glowEffect(isActive: true, color: .red)

        Text("Error")
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .shakeEffect(isActive: false)
    }
    .padding(50)
}
