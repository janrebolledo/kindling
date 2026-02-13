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
    @State private var screenshotCount: Int = 0
    @State private var player: AVPlayer = AVPlayer(
        url: Bundle.main.url(forResource: "onboarding", withExtension: ".mp4")!
    )

    var body: some View {
        if step == 1 {
            OnboardingStartView(
                step: $step,
                cards: $cards,
                screenshotCount: $screenshotCount,
                firstCardLoaded: $firstCardLoaded
            )
        }
        if step == 2 {
            OnboardingAnimationView(
                player: $player,
            )
        }
        if step == 3 {
            SignUpCaptureView(
                cards: $cards,
                step: $step,
                screenshotCount: $screenshotCount
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
