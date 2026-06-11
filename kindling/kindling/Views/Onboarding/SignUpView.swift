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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            Image(colorScheme == .dark ? "gradient dark" : "gradient light")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Title + logo
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
                .padding(.top, 24)

                Text("play has never been easier")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                // Decorative card pair
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Left card (partially off-screen)
                        OnboardingSignUpCard(
                            day: "Saturday",
                            title: "The Garage Sale",
                            location: "Fullerton, CA",
                            detail: "$12.50 Tickets",
                            topColors: [Color(red: 0.62, green: 0.50, blue: 0.38), Color(red: 0.44, green: 0.35, blue: 0.27)],
                            cardBackground: Color(red: 248/255, green: 246/255, blue: 240/255)
                        )
                        .frame(width: 280)
                        .offset(x: -geo.size.width * 0.27)

                        // Right card (visible)
                        OnboardingSignUpCard(
                            day: "Sunday",
                            title: "Do Coffee",
                            location: "Yorba Linda, CA",
                            detail: "Open · Closes at 4 PM",
                            topColors: [Color(red: 0.30, green: 0.22, blue: 0.18), Color(red: 0.18, green: 0.14, blue: 0.12)],
                            cardBackground: Color(red: 248/255, green: 246/255, blue: 242/255)
                        )
                        .frame(width: 280)
                        .offset(x: geo.size.width * 0.5 + 10)
                    }
                }
                .frame(height: 260)
                .padding(.horizontal, -48)
                .clipped()

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { continueButtonTapped() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .medium))
                            Text("continue with Apple")
                                .font(.system(size: 20, weight: .medium))
                                .tracking(-0.5)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }

                    Text("By continuing, you agree to kindling's \(Text("Terms & Conditions").underline()) and acknowledge the \(Text("Privacy Policy").underline()).")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
                        .multilineTextAlignment(.center)
                        .tracking(-0.12)
                }
                .padding(.bottom, 16)
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

private struct OnboardingSignUpCard: View {
    let day: String
    let title: String
    let location: String
    let detail: String
    let topColors: [Color]
    let cardBackground: Color

    var body: some View {
        VStack(spacing: 0) {
            // Color block top
            LinearGradient(colors: topColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 150)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(day)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.primary)
                Text(location)
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundColor(.secondary)
                    .opacity(0.5)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
}
