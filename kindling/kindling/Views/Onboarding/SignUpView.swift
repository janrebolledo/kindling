import AuthenticationServices
import SwiftUI

struct SignUpView: View {
    @Binding var cards: [ItemWrapper]
    var onEmail: () -> Void

    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var appleSignIn = AppleSignInManager()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var errorTransitionAnimation: Animation {
        .easeOut(duration: 0.12)
    }

    private var errorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: -4))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            OnboardingWarmGradient()

            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("sign up for")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .foregroundStyle(.primary)

                    Image(colorScheme == .dark ? "kindling white" : "kindling black")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 39)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                .padding(.horizontal, 24)

                Text("play has never been easier")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 55)
                    .padding(.horizontal, 24)

                OnboardingCardCarousel(cards: cards, speed: 18)
                    .padding(.top, 36)

                Spacer()

                VStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .tracking(-0.2)
                            .foregroundStyle(Color(red: 222 / 255, green: 51 / 255, blue: 43 / 255))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 4)
                            .transition(errorTransition)
                    }

                    OnboardingPrimaryButton(
                        title: "sign up with Apple",
                        systemName: "apple.logo",
                        isEnabled: !isLoading
                    ) {
                        continueButtonTapped()
                    }

                    OnboardingSecondaryButton(title: "sign up with email") {
                        withAnimation(OnboardingMotion.step(reduceMotion)) {
                            onEmail()
                        }
                    }
                    .disabled(isLoading)

                    OnboardingLegalText()
                        .padding(.top, 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    func continueButtonTapped() {
        Task {
            isLoading = true
            OnboardingHomeCache.savePending(cards)
            withAnimation(errorTransitionAnimation) {
                errorMessage = nil
            }
            defer { isLoading = false }
            do {
                try await appleSignIn.signIn()
                await InitializeCollection(items: cards)
            } catch {
                if let authError = error as? ASAuthorizationError,
                   authError.code == .canceled
                {
                    OnboardingHomeCache.clearPending()
                    return
                }
                OnboardingHomeCache.clearPending()
                withAnimation(errorTransitionAnimation) {
                    errorMessage = error.localizedDescription.lowercased()
                }
            }
        }
    }
}
