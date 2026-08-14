//
//  AccountDeletion.swift
//  kindling
//
//  Deletes the signed-in user's server-side data, auth record, and local
//  caches. Sign in with Apple must not restore the previous account.
//

import Foundation
import Supabase

enum AccountDeletion {
    enum DeletionError: LocalizedError {
        case notSignedIn
        case failed

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "You're not signed in."
            case .failed:
                return "Couldn't delete your account. Try again."
            }
        }
    }

    /// Wipes the current account. Throws if owned data could not be removed.
    static func deleteCurrentAccount() async throws {
        guard let userID = supabase.auth.currentUser?.id else {
            throw DeletionError.notSignedIn
        }

        let session = try await supabase.auth.session
        let remoteDeleted = await deleteViaBackend(accessToken: session.accessToken)

        if !remoteDeleted {
            try await deleteOwnedRows(userID: userID)
            try? await clearProfileMetadata()
        }

        ParsedScreenshotsService.clearAllLocal(for: userID)
        try? await supabase.auth.signOut()
    }

    /// Asks the backend (service role) to hard-delete the auth user. Returns
    /// false when the backend is unreachable so the client can still wipe rows.
    private static func deleteViaBackend(accessToken: String) async -> Bool {
        var request = URLRequest(url: backendBaseURL.appendingPathComponent("account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return false }
            return true
        } catch {
            dump(error)
            return false
        }
    }

    private static func deleteOwnedRows(userID: UUID) async throws {
        do {
            try await supabase
                .from("collection_items")
                .delete()
                .eq("user_id", value: userID)
                .execute()
            try await supabase
                .from("collections")
                .delete()
                .eq("user_id", value: userID)
                .execute()
            try await supabase
                .from("user_data")
                .delete()
                .eq("user_id", value: userID)
                .execute()
        } catch {
            dump(error)
            throw DeletionError.failed
        }
    }

    /// Clears names stored on the auth user so a reused Apple identity does
    /// not come back with the previous display name.
    private static func clearProfileMetadata() async throws {
        try await supabase.auth.update(
            user: UserAttributes(
                data: [
                    "display_name": .string(""),
                    "full_name": .string(""),
                    "given_name": .string(""),
                    "family_name": .string(""),
                    "name": .string(""),
                ]
            )
        )
    }
}
