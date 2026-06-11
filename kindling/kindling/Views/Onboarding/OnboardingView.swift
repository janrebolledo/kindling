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
    @State private var cards: [ItemWrapper] = []
    @State private var screenshotImages: [UIImage] = []
    @State private var totalScreenshotCount: Int = 0
    @State private var totalSizeGB: Double = 0
    @State private var isProcessing: Bool = false

    var body: some View {
        currentStepView
            .safeAreaInset(edge: .top, spacing: 0) {
                if step > 1 {
                    OnboardingProgressHeader(currentStep: step - 1)
                }
            }
            .onAppear {
                // Resume onboarding: if we parsed items in a previous session but
                // the user closed the app before signing up, restore them and jump
                // straight to the sign-up capture step.
                if cards.isEmpty {
                    let drafts = OnboardingDraftCache.load()
                    if !drafts.isEmpty {
                        cards = drafts
                        if step < 4 { step = 4 }
                    }
                }
            }
    }

    @ViewBuilder
    private var currentStepView: some View {
        if step == 1 {
            OnboardingStartView(step: $step)
        } else if step == 2 {
            OnboardingPermissionsView(
                step: $step,
                cards: $cards,
                screenshotImages: $screenshotImages,
                totalScreenshotCount: $totalScreenshotCount,
                totalSizeGB: $totalSizeGB,
                isProcessing: $isProcessing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if step == 3 {
            OnboardingScreenshotSummaryView(
                step: $step,
                screenshotImages: screenshotImages,
                totalCount: totalScreenshotCount,
                totalSizeGB: totalSizeGB,
                isProcessing: $isProcessing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if step == 4 {
            SignUpCaptureView(cards: $cards, step: $step)
        } else {
            SignUpView(cards: $cards)
        }
    }
}

#Preview {
    OnboardingView()
}

