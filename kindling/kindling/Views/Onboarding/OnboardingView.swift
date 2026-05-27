import AVKit
//
//  OnboardingView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/24/26.
//
import SwiftUI

struct OnboardingView: View {
    @State private var step: Int = 1
    @State private var accessGranted = false
    @State private var cards: [ItemWrapper] = []
    @State private var firstCardLoaded: Bool = false

    var body: some View {
        if step == 1 {
            OnboardingStartView(step: $step)
        }
        if step == 2 {
            OnboardingPermissionsView(
                step: $step,
                cards: $cards,
                firstCardLoaded: $firstCardLoaded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if step == 3 {
            SignUpCaptureView(
                cards: $cards,
                step: $step,
            )
        }
        if step == 4 {
            SignUpView(cards: $cards)
        }
    }
}

#Preview {
    OnboardingView()
}
