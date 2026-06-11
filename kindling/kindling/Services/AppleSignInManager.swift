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
                let fullNameString = nameParts.joined(separator: " ")
                try? await supabase.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name": .string(fullNameString),
                            "given_name": .string(fullName.givenName ?? ""),
                            "family_name": .string(fullName.familyName ?? ""),
                        ]
                    )
                )
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
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
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
