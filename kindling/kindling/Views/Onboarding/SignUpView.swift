import Supabase
//
//  SignUpView.swift
//  kindling
//
import AuthenticationServices
import SwiftUI

struct SignUpView: View {
    @Binding var cards: [ItemWrapper]
    @State private var isLoading: Bool = false
    @State var result: Result<Void, Error>?
    @State private var appleSignIn = AppleSignInManager()
    @State private var emailMode: EmailAuthMode?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let emailMode {
                EmailAuthView(cards: $cards, mode: emailMode)
                    .transition(.opacity)
            } else {
                landing
                    .transition(.opacity)
            }
        }
    }

    private var landing: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Image(colorScheme == .dark ? "gradient dark" : "gradient light")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 363)
                    .clipped()

                Spacer(minLength: 0)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text("sign up for")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .foregroundColor(.primary)

                    Image(colorScheme == .dark ? "kindling white" : "kindling black")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 39)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 58)

                Text("play has never been easier")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 55)

                OnboardingCardCarousel(cards: cards, speed: 18)
                    .frame(height: 271)
                    .padding(.horizontal, -48)
                    .padding(.top, 63)

                Spacer()

                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) { continueButtonTapped() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .medium))
                                Text("sign up with Apple")
                                    .font(.system(size: 20, weight: .medium))
                                    .tracking(-0.5)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .disabled(isLoading)

                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) { emailMode = .signUp }
                        } label: {
                            Text("sign up with email")
                                .font(.system(size: 20, weight: .medium))
                                .tracking(-0.5)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, -32)

                    OnboardingLegalText()
                        .padding(.horizontal, -24)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 48)
        }
    }

    func continueButtonTapped() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await appleSignIn.signIn()
                result = .success(())
                await InitializeCollection(items: cards)
            } catch {
                if let authError = error as? ASAuthorizationError,
                   authError.code == .canceled {
                    return
                }
                print("Sign in with Apple failed: \(error.localizedDescription)")
                result = .failure(error)
            }
        }
    }
}
