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
    private static let legacyDefaultsKey = "parsedScreenshotLocalIDs"
    private static let onboardingDefaultsKey = "parsedScreenshotLocalIDs.onboarding"

    private let defaultsKey: String

    init(userID: UUID? = supabase.auth.currentUser?.id) {
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

    func loadLocalParsedIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        return Set(array)
    }

    func saveLocalParsedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
    }

    func markAsParsed(_ newIDs: [String]) {
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
