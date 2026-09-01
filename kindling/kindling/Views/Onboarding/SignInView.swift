import AuthenticationServices
import SwiftUI

struct SignInView: View {
    var onEmail: () -> Void
    var onSignUp: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var appleSignIn = AppleSignInManager()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            OnboardingWarmGradient()

            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("sign in to")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .foregroundStyle(.primary)

                    Text("kindling")
                        .font(.system(size: 39, weight: .medium))
                        .tracking(-1.8)
                        .foregroundStyle(.primary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 32)
                .padding(.horizontal, 24)

                Text("welcome back")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 55)
                    .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .tracking(-0.2)
                            .foregroundStyle(Color(red: 222 / 255, green: 51 / 255, blue: 43 / 255))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 4)
                    }

                    OnboardingPrimaryButton(
                        title: "sign in with Apple",
                        systemName: "apple.logo",
                        isEnabled: !isLoading
                    ) {
                        signInWithApple()
                    }

                    OnboardingSecondaryButton(title: "sign in with email") {
                        withAnimation(OnboardingMotion.step(reduceMotion)) {
                            onEmail()
                        }
                    }
                    .disabled(isLoading)

                    Button {
                        withAnimation(OnboardingMotion.step(reduceMotion)) {
                            onSignUp()
                        }
                    } label: {
                        Text("don't have an account? \(Text("sign up").foregroundStyle(.primary).underline())")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.32)
                            .foregroundStyle(kindlingMuted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(OnboardingPressStyle())
                    .disabled(isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func signInWithApple() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }

            do {
                try await appleSignIn.signIn()
            } catch {
                if let authError = error as? ASAuthorizationError,
                   authError.code == .canceled
                {
                    return
                }
                errorMessage = error.localizedDescription.lowercased()
            }
        }
    }
}

#Preview {
    SignInView(onEmail: {}, onSignUp: {})
}
