//
//  EmailAuthView.swift
//  kindling
//

import Supabase
import SwiftUI

enum EmailAuthMode: Equatable {
    case signUp
    case signIn
}

struct EmailAuthView: View {
    @Binding var cards: [ItemWrapper]
    @Binding var mode: EmailAuthMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isPasswordStep = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .signIn && !isPasswordStep {
            return trimmed.contains("@") && !isLoading
        }
        return trimmed.contains("@") && password.count >= 6 && !isLoading
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    titleBlock

                    credentials
                        .padding(.horizontal, 12)
                        .padding(.top, 35)

                    if mode == .signIn && isPasswordStep {
                        Button(action: sendReset) {
                            Text("forgot password?")
                                .font(.system(size: 16, weight: .medium))
                                .tracking(-0.4)
                                .underline()
                                .foregroundStyle(kindlingMuted)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(OnboardingPressStyle())
                        .disabled(isLoading)
                        .padding(.horizontal, 16)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .tracking(-0.2)
                            .foregroundStyle(Color(red: 222 / 255, green: 51 / 255, blue: 43 / 255))
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    } else if let infoMessage {
                        Text(infoMessage)
                            .font(.system(size: 13))
                            .tracking(-0.2)
                            .foregroundStyle(kindlingMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 12)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 24)

                    footer
                }
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .background {
            ZStack(alignment: .top) {
                Color(.systemBackground)
                OnboardingWarmGradient()
            }
            .ignoresSafeArea()
        }
        .onChange(of: mode) { _, _ in
            password = ""
            showPassword = false
            isPasswordStep = false
            errorMessage = nil
            infoMessage = nil
            focusedField = .email
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 0) {
            Text(mode == .signUp ? "sign up with\nemail" : "sign in with\nemail")
                .font(.system(size: 36, weight: .medium))
                .tracking(-0.9)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 32)

            Text(mode == .signUp ? "play has never been easier" : "welcome back")
                .font(.system(size: 20, weight: .medium))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 48)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var credentials: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField(
                label: "email",
                text: $email,
                isSecure: false,
                prompt: "you@icloud.com"
            )
            .focused($focusedField, equals: .email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            if mode == .signUp || isPasswordStep {
                labeledField(
                    label: "password",
                    text: $password,
                    isSecure: true,
                    prompt: "••••••••"
                )
                .focused($focusedField, equals: .password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .submitLabel(.go)
                .onSubmit { submit() }
            }
        }
    }

    private func labeledField(
        label: String,
        text: Binding<String>,
        isSecure: Bool,
        prompt: String
    ) -> some View {
        let promptText = Text(prompt)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(kindlingMuted.opacity(0.55))

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 10))
                    .tracking(-0.125)
                    .foregroundStyle(kindlingMuted)

                Group {
                    if isSecure, !showPassword {
                        SecureField("", text: text, prompt: promptText)
                    } else {
                        TextField("", text: text, prompt: promptText)
                    }
                }
                .font(.system(size: 16, weight: .medium))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Spacer(minLength: 8)

            if isSecure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(kindlingMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OnboardingPressStyle())
                .accessibilityLabel(showPassword ? "hide password" : "show password")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color("raisedSurface"),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var footer: some View {
        VStack(spacing: 16) {
            OnboardingPrimaryButton(
                title: mode == .signIn && isPasswordStep ? "sign in →" : "continue →",
                isEnabled: canSubmit
            ) {
                submit()
            }

            Button {
                withAnimation(OnboardingMotion.step(reduceMotion)) {
                    errorMessage = nil
                    infoMessage = nil
                    mode = mode == .signUp ? .signIn : .signUp
                }
            } label: {
                switcherLabel
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.32)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(isLoading)

            if mode == .signUp {
                OnboardingLegalText()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var switcherLabel: Text {
        if mode == .signUp {
            return Text("already have an account? \(Text("sign in").foregroundColor(.primary).underline())")
                .foregroundColor(kindlingMuted)
        }
        return Text("don't have an account? \(Text("sign up").foregroundColor(.primary).underline())")
            .foregroundColor(kindlingMuted)
    }

    private func submit() {
        guard canSubmit else { return }

        if mode == .signIn && !isPasswordStep {
            withAnimation(OnboardingMotion.step(reduceMotion)) {
                isPasswordStep = true
                focusedField = .password
            }
            return
        }

        focusedField = nil
        Task { await authenticate() }
    }

    private func sendReset() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@") else {
            focusedField = .email
            errorMessage = "enter your email first"
            infoMessage = nil
            return
        }
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await supabase.auth.resetPasswordForEmail(
                    trimmed,
                    redirectTo: KindlingLegal.privacyURL.deletingLastPathComponent()
                )
                errorMessage = nil
                infoMessage = "check your email for a reset link"
            } catch {
                infoMessage = nil
                errorMessage = error.localizedDescription.lowercased()
            }
        }
    }

    @MainActor
    private func authenticate() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        infoMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        OnboardingHomeCache.savePending(cards)

        do {
            if mode == .signUp {
                let response = try await supabase.auth.signUp(
                    email: trimmedEmail,
                    password: password
                )
                if response.session == nil {
                    infoMessage = "check your email to finish signing up"
                    return
                }
            } else {
                _ = try await supabase.auth.signIn(
                    email: trimmedEmail,
                    password: password
                )
            }

            await ensureUsernameExists()
            if mode == .signUp {
                await InitializeCollection(items: cards)
            }
        } catch {
            OnboardingHomeCache.clearPending()
            errorMessage = error.localizedDescription.lowercased()
        }
    }
}

#Preview {
    EmailAuthView(cards: .constant([]), mode: .constant(.signUp))
}
