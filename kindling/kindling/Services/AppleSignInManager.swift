//
//  AppleSignInManager.swift
//  kindling
//
//  Handles native Sign in with Apple and exchanges the identity token
//  with Supabase Auth via signInWithIdToken.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

@MainActor
final class AppleSignInManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var currentNonce: String?

    /// Performs the native Sign in with Apple flow and signs the user into Supabase.
    func signIn() async throws {
        let credential = try await requestAppleCredential()

        guard let idTokenData = credential.identityToken,
              let idToken = String(data: idTokenData, encoding: .utf8)
        else {
            throw AppleSignInError.missingIdentityToken
        }

        try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: currentNonce
            )
        )

        // Apple only provides the user's full name on the first sign-in.
        // Persist it to user metadata when available.
        if let fullName = credential.fullName {
            var nameParts: [String] = []
            if let givenName = fullName.givenName { nameParts.append(givenName) }
            if let middleName = fullName.middleName { nameParts.append(middleName) }
            if let familyName = fullName.familyName { nameParts.append(familyName) }

            if !nameParts.isEmpty {
                let fullNameString = nameParts.joined(separator: " ").lowercased()
                do {
                    try await supabase.auth.update(
                        user: UserAttributes(
                            data: [
                                "full_name": .string(fullNameString),
                                "given_name": .string((fullName.givenName ?? "").lowercased()),
                                "family_name": .string((fullName.familyName ?? "").lowercased()),
                            ]
                        )
                    )
                } catch {
                    dump(error)
                }
            }
        }

        await ensureUsernameExists()
    }

    /// Generates and persists a default username from the email prefix the first
    /// time an account signs in. No-op when the user already has a username.
    private func ensureUsernameExists() async {
        guard let user = supabase.auth.currentUser else { return }

        do {
            let rows: [UsernameRow] =
                try await supabase
                .from("user_data")
                .select("username")
                .eq("user_id", value: user.id)
                .execute()
                .value
            if let existing = rows.first?.username, !existing.isEmpty { return }
        } catch {
            dump(error)
            return
        }

        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        var base = (user.email?.split(separator: "@").first.map(String.init) ?? "user")
            .lowercased()
            .filter { allowed.contains($0) }
        if base.count < 3 { base += "user" }
        base = String(base.prefix(20))

        // Build candidates: the base first, then base + a numeric suffix.
        func candidate(_ index: Int) -> String {
            guard index > 0 else { return base }
            let suffix = String(index)
            let trimmed = String(base.prefix(20 - suffix.count))
            return trimmed + suffix
        }

        for attempt in 0...50 {
            let candidate =
                attempt <= 9 ? candidate(attempt) : candidate(Int.random(in: 100...9999))
            do {
                let available: Bool =
                    try await supabase
                    .rpc("is_username_available", params: ["candidate": candidate])
                    .execute()
                    .value
                if !available { continue }

                try await supabase
                    .from("user_data")
                    .upsert(
                        UsernameInsert(user_id: user.id, username: candidate),
                        onConflict: "user_id"
                    )
                    .execute()
                return
            } catch let error as PostgrestError where error.code == "23505" {
                // Lost a race; try the next candidate.
                continue
            } catch {
                dump(error)
                return
            }
        }
    }

    private func requestAppleCredential() async throws -> ASAuthorizationAppleIDCredential {
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.invalidCredential)
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let scene else {
            fatalError("Sign in with Apple requires a connected window scene.")
        }
        return scene.keyWindow ?? ASPresentationAnchor(windowScene: scene)
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

enum AppleSignInError: LocalizedError {
    case missingIdentityToken
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken:
            return "Apple did not return an identity token."
        case .invalidCredential:
            return "Received an invalid Apple credential."
        }
    }
}

private struct UsernameRow: Decodable {
    let username: String?
}

private struct UsernameInsert: Encodable {
    let user_id: UUID
    let username: String
}
