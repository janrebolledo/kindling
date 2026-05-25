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
    private let defaultsKey = "parsedScreenshotLocalIDs"

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
