//
//  ParsedScreenshotsService.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Foundation
import Supabase

struct UserDataPayload: Encodable {
    let user_id: UUID
    let parsed_screenshot_ids: [String]
}

class ParsedScreenshotsService {
    private nonisolated static let legacyDefaultsKey = "parsedScreenshotLocalIDs"
    private nonisolated static let onboardingDefaultsKey = "parsedScreenshotLocalIDs.onboarding"

    private let defaultsKey: String

    convenience init() {
        self.init(userID: supabase.auth.currentUser?.id)
    }

    nonisolated init(userID: UUID?) {
        if let userID {
            defaultsKey = "parsedScreenshotLocalIDs.\(userID.uuidString)"
        } else {
            defaultsKey = Self.onboardingDefaultsKey
        }

        // Move installs from the old global key exactly once. Once removed, a
        // later account on this device cannot inherit another user's history.
        if let legacy = UserDefaults.standard.stringArray(forKey: Self.legacyDefaultsKey) {
            var scoped = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            scoped.formUnion(legacy)
            UserDefaults.standard.set(Array(scoped), forKey: defaultsKey)
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        }
    }

    nonisolated func loadLocalParsedIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set(array)
    }

    nonisolated func saveLocalParsedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
    }

    nonisolated func clearLocal() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Drops on-device parse history and onboarding drafts for this user so a
    /// later sign-in with the same Apple ID cannot reuse them.
    static func clearAllLocal(for userID: UUID) {
        ParsedScreenshotsService(userID: userID).clearLocal()
        UserDefaults.standard.removeObject(forKey: onboardingDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        OnboardingDraftCache.clear()
    }

    nonisolated func markAsParsed(_ newIDs: [String]) {
        var existing = loadLocalParsedIDs()
        existing.formUnion(newIDs)
        saveLocalParsedIDs(existing)
    }

    /// Claims screenshots indexed before sign-up for the newly-created user.
    static func claimOnboardingIDs(for userID: UUID) {
        let defaults = UserDefaults.standard
        let onboarding = Set(
            defaults.stringArray(forKey: onboardingDefaultsKey) ?? []
        )
        guard !onboarding.isEmpty else { return }

        let userService = ParsedScreenshotsService(userID: userID)
        userService.markAsParsed(Array(onboarding))
        defaults.removeObject(forKey: onboardingDefaultsKey)
    }

    func syncToSupabase(userID: UUID) async throws {
        let ids = loadLocalParsedIDs()
        let payload = UserDataPayload(
            user_id: userID,
            parsed_screenshot_ids: Array(ids)
        )
        try await supabase
            .from("user_data")
            .upsert(payload, onConflict: "user_id")
            .execute()
    }

    func fetchAndMergeFromSupabase(userID: UUID) async throws {
        let response: [UserData] = try await supabase
            .from("user_data")
            .select()
            .eq("user_id", value: userID)
            .execute()
            .value

        if let remote = response.first {
            var local = loadLocalParsedIDs()
            local.formUnion(remote.parsed_screenshot_ids)
            saveLocalParsedIDs(local)
        }
    }
}
