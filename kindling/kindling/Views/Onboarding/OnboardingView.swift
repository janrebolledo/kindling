//
//  OnboardingView.swift
//  kindling
//
//  Created by Jan Rebolledo on 1/24/26.
//
import SwiftUI

enum OnboardingRoute: Equatable {
    case start
    case permissions
    case summary
    case capture
    case signUp
    case email(EmailAuthMode)

    var progressStep: Int? {
        switch self {
        case .start, .email(.signIn):
            return nil
        case .permissions:
            return 1
        case .summary:
            return 2
        case .capture:
            return 3
        case .signUp, .email(.signUp):
            return 4
        }
    }

    var showsHeader: Bool {
        self != .start
    }

    /// Stable identity so email sign-in ↔ sign-up does not remount the form.
    var screenID: String {
        switch self {
        case .start: "start"
        case .permissions: "permissions"
        case .summary: "summary"
        case .capture: "capture"
        case .signUp: "signUp"
        case .email: "email"
        }
    }
}

struct OnboardingView: View {
    @State private var route: OnboardingRoute = .start
    @State private var cards: [ItemWrapper] = []
    @State private var screenshotImages: [UIImage] = []
    @State private var totalScreenshotCount: Int = 0
    @State private var totalSizeGB: Double = 0
    @State private var isProcessing: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            currentStepView
                .id(route.screenID)
                .transition(.opacity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if route.showsHeader {
                OnboardingProgressHeader(currentStep: route.progressStep)
            }
        }
        .animation(OnboardingMotion.step(reduceMotion), value: route)
        .onAppear {
            // Resume onboarding: if we parsed items in a previous session but
            // the user closed the app before signing up, restore them and jump
            // straight to the sign-up capture step.
            if cards.isEmpty {
                let drafts = OnboardingDraftCache.load()
                if !drafts.isEmpty {
                    cards = drafts
                    if route == .start || route == .permissions || route == .summary {
                        route = .capture
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch route {
        case .start:
            OnboardingStartView(
                onContinue: { route = .permissions },
                onSignIn: { route = .email(.signIn) }
            )
        case .permissions:
            OnboardingPermissionsView(
                onContinue: { route = .summary },
                cards: $cards,
                screenshotImages: $screenshotImages,
                totalScreenshotCount: $totalScreenshotCount,
                totalSizeGB: $totalSizeGB,
                isProcessing: $isProcessing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .summary:
            OnboardingScreenshotSummaryView(
                onContinue: { route = .capture },
                screenshotImages: screenshotImages,
                totalCount: totalScreenshotCount,
                totalSizeGB: totalSizeGB,
                isProcessing: $isProcessing
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .capture:
            SignUpCaptureView(
                cards: $cards,
                onContinue: { route = .signUp }
            )
        case .signUp:
            SignUpView(
                cards: $cards,
                onEmail: { route = .email(.signUp) }
            )
        case .email:
            EmailAuthView(
                cards: $cards,
                mode: emailModeBinding
            )
        }
    }

    private var emailModeBinding: Binding<EmailAuthMode> {
        Binding(
            get: {
                if case .email(let mode) = route { return mode }
                return .signUp
            },
            set: { route = .email($0) }
        )
    }
}

#Preview {
    OnboardingView()
}
