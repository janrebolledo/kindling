//
//  OnboardingChrome.swift
//  kindling
//
//  Shared onboarding materials: warm gradient, primary pill, press
//  feedback, and the privacy footnote used under capture/summary.
//

import SwiftUI

let kindlingMuted = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

enum OnboardingMotion {
    static func step(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .spring(duration: 0.35, bounce: 0)
    }
}

enum CardSwipeMotion {
    static let outgoingOffset: CGFloat = 230
    static let handoffNanoseconds: UInt64 = 180_000_000

    static func transition(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.28)
    }
}

struct OnboardingPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct OnboardingWarmGradient: View {
    var height: CGFloat = 363
    var grayscale: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "gradient dark" : "gradient light")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .grayscale(grayscale ? 0.45 : 0)
            .ignoresSafeArea()
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var systemName: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(OnboardingPressStyle())
        .disabled(!isEnabled)
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Color("raisedSurface"),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
        }
        .buttonStyle(OnboardingPressStyle())
    }
}

struct OnboardingPrivacyNote: View {
    var body: some View {
        Text("kindling cannot view your photos, everything is stored on device :)")
            .font(.system(size: 12))
            .foregroundStyle(kindlingMuted)
            .multilineTextAlignment(.center)
            .tracking(-0.12)
    }
}
