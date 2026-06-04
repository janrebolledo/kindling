//
//  OnboardingProgressHeader.swift
//  kindling
//

import SwiftUI

struct OnboardingProgressHeader: View {
    let currentStep: Int  // 1-based, out of 4

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Image(colorScheme == .dark ? "kindling white" : "kindling black")
                .resizable()
                .scaledToFit()
                .frame(height: 21)

            Spacer()

            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary)
                        .opacity(i == currentStep ? 0.8 : 0.3)
                        .frame(width: i == currentStep ? 69 : 20, height: 5)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

#Preview {
    VStack {
        OnboardingProgressHeader(currentStep: 1)
        OnboardingProgressHeader(currentStep: 2)
        OnboardingProgressHeader(currentStep: 3)
    }
}
