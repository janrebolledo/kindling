//
//  EmailAuthView.swift
//  kindling
//

import Supabase
import SwiftUI

enum EmailAuthMode {
    case signUp
    case signIn
}

private let kindlingMuted = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

struct EmailAuthView: View {
    @Binding var cards: [ItemWrapper]
    @State private var mode: EmailAuthMode

    init(cards: Binding<[ItemWrapper]>, mode: EmailAuthMode) {
        self._cards = cards
        self._mode = State(initialValue: mode)
    }

    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var canSubmit: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && password.count >= 6 && !isLoading
    }

    var body: some View {
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
                Text(mode == .signUp ? "sign up with email" : "sign in with email")
                    .font(.system(size: 36, weight: .medium))
                    .tracking(-0.9)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 58)

                Text(mode == .signUp ? "play has never been easier" : "welcome back")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    field(placeholder: "email", text: $email, isSecure: false)
                        .focused($focusedField, equals: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }

                    field(placeholder: "password", text: $password, isSecure: true)
                        .focused($focusedField, equals: .password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }

                    if mode == .signIn {
                        Button(action: sendReset) {
                            Text("forgot password?")
                                .font(.system(size: 12))
                                .underline()
                                .foregroundColor(kindlingMuted)
                                .tracking(-0.12)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 40)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .tracking(-0.2)
                        .foregroundStyle(Color(red: 1, green: 56 / 255, blue: 60 / 255))
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                } else if let infoMessage {
                    Text(infoMessage)
                        .font(.system(size: 13))
                        .tracking(-0.2)
                        .foregroundStyle(kindlingMuted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                }

                Spacer()

                VStack(spacing: 8) {
                    Button(action: submit) {
                        Text(mode == .signUp ? "continue →" : "sign in →")
                            .font(.system(size: 20, weight: .medium))
                            .tracking(-0.5)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .opacity(canSubmit ? 1 : 0.5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .padding(.horizontal, -32)

                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            errorMessage = nil
                            infoMessage = nil
                            mode = mode == .signUp ? .signIn : .signUp
                        }
                    } label: {
                        switcherLabel
                            .font(.system(size: 20, weight: .medium))
                            .tracking(-0.5)
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .padding(.horizontal, -32)
                    .frame(height: 56)

                    if mode == .signUp {
                        OnboardingLegalText()
                            .padding(.horizontal, -24)
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 48)
        }
        .onChange(of: mode) { _, _ in
            password = ""
            focusedField = .email
        }
    }

    private var switcherLabel: Text {
        if mode == .signUp {
            return Text("already have an account? ").foregroundColor(kindlingMuted)
                + Text("sign in").foregroundColor(.primary).underline()
        }
        return Text("don't have an account? ").foregroundColor(kindlingMuted)
            + Text("sign up").foregroundColor(.primary).underline()
    }

    private func field(placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        Group {
            if isSecure {
                SecureField("", text: text, prompt: prompt(placeholder))
            } else {
                TextField("", text: text, prompt: prompt(placeholder))
            }
        }
        .font(.system(size: 20, weight: .medium))
        .tracking(-0.5)
        .foregroundColor(.primary)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 56)
        .background(Color("raisedSurface"), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, -32)
    }

    private func prompt(_ placeholder: String) -> Text {
        Text(placeholder)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(kindlingMuted)
    }

    private func submit() {
        guard canSubmit else { return }
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
                try await supabase.auth.resetPasswordForEmail(trimmed)
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
            await InitializeCollection(items: cards)
        } catch {
            errorMessage = error.localizedDescription.lowercased()
        }
    }
}

#Preview {
    EmailAuthView(cards: .constant([]), mode: .signUp)
}
