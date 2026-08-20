//
//  Supabase.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://bfbaqyhyxergcpsyhzcc.supabase.co")!,
    supabaseKey: "sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)

extension User {
    /// The user's display name, derived from auth metadata
    /// (`display_name`, then `full_name`, then `name`), falling back to the
    /// email prefix. Always lowercase to match the rest of the UI.
    var displayName: String {
        for key in ["display_name", "full_name", "name"] {
            if let value = userMetadata[key]?.stringValue,
                !value.isEmpty
            {
                return value.lowercased()
            }
        }
        let prefix = email?.split(separator: "@").first.map(String.init) ?? "you"
        return prefix.lowercased()
    }
}

struct Item: Codable, Identifiable {
    let id: Int
    let name: String?
    let type: String?
    let description: String?
    let media_url: String?
    let location_type: String?
    let location_emoji: String?
    let duration: String?
    let date: String?
    let time: String?
    let place_id: String?
    let created_at: String?

    var locationTypeLabel: String? {
        let label = [location_emoji, location_type]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return label.isEmpty ? nil : label
    }
}

struct collection: Encodable, Identifiable {
    let id: Int
    let name: String?
    let emoji: String?
    let user_id: UUID?
}

struct collection_item: Encodable, Decodable, Identifiable {
    let id: Int
    let created_at: String?
    let local_id: String
    let idea_id: Int
    let user_id: UUID
    let collection_id: Int?
}

struct UserData: Decodable {
    let id: Int
    let user_id: UUID
    let parsed_screenshot_ids: [String]
    let created_at: String?
    let preferred_transport_type: String?
    let username: String?
}

struct UserAnalytics: Equatable, Sendable {
    let screenshotsProcessed: Int
    let ideasMade: Int
    let sharedIdeaIDs: [Int]
    let parseSuccessRate: Double
    let ideasPerScreenshot: Double
    let ideasDeleted: Int
    let shareLinkOpens: Int

    var ideasShared: Int { sharedIdeaIDs.count }
}

private struct AnalyticsUserDataRow: Decodable {
    let parsed_screenshot_ids: [String]
}

private struct AnalyticsCollectionItemRow: Decodable {
    let local_id: String
    let idea_id: Int
}

private struct IdeaShareInsert: Encodable {
    let user_id: UUID
    let idea_id: Int
}

private struct IdeaShareRow: Decodable {
    let idea_id: Int
}

private struct AnalyticsCountRow: Decodable {
    let id: Int
}

private struct AnalyticsDeletedItemRow: Decodable {
    let local_id: String
}

private struct IdeaDeletionInsert: Encodable {
    let user_id: UUID
    let idea_id: Int
    let local_id: String
}

enum UserAnalyticsService {
    static func load() async throws -> UserAnalytics {
        guard let userID = supabase.auth.currentUser?.id else {
            return UserAnalytics(
                screenshotsProcessed: 0,
                ideasMade: 0,
                sharedIdeaIDs: [],
                parseSuccessRate: 0,
                ideasPerScreenshot: 0,
                ideasDeleted: 0,
                shareLinkOpens: 0
            )
        }

        let userData: [AnalyticsUserDataRow] = try await supabase
            .from("user_data")
            .select("parsed_screenshot_ids")
            .eq("user_id", value: userID)
            .execute()
            .value

        let collectionItems: [AnalyticsCollectionItemRow] = try await supabase
            .from("collection_items")
            .select("local_id, idea_id")
            .eq("user_id", value: userID)
            .execute()
            .value

        let shares: [IdeaShareRow] = try await supabase
            .from("idea_shares")
            .select("idea_id")
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .execute()
            .value

        let deletions: [AnalyticsDeletedItemRow] = try await supabase
            .from("idea_deletions")
            .select("local_id")
            .eq("user_id", value: userID)
            .execute()
            .value

        let shareOpens: [AnalyticsCountRow] = try await supabase
            .from("idea_share_opens")
            .select("id")
            .eq("owner_user_id", value: userID)
            .execute()
            .value

        let processedScreenshotIDs = Set(
            userData.first?.parsed_screenshot_ids ?? []
        )
        let successfulScreenshotIDs = Set(
            collectionItems.compactMap { item in
                processedScreenshotIDs.contains(item.local_id)
                    ? item.local_id
                    : nil
            }
        ).union(
            deletions.compactMap { item in
                processedScreenshotIDs.contains(item.local_id)
                    ? item.local_id
                    : nil
            }
        )
        let ideasMade = Set(collectionItems.map(\.idea_id)).count
        let screenshotCount = processedScreenshotIDs.count

        return UserAnalytics(
            screenshotsProcessed: screenshotCount,
            ideasMade: ideasMade,
            sharedIdeaIDs: shares.map(\.idea_id),
            parseSuccessRate: screenshotCount > 0
                ? Double(successfulScreenshotIDs.count) / Double(screenshotCount)
                : 0,
            ideasPerScreenshot: screenshotCount > 0
                ? Double(ideasMade) / Double(screenshotCount)
                : 0,
            ideasDeleted: deletions.count,
            shareLinkOpens: shareOpens.count
        )
    }

    /// Records one unique share per user/idea. Re-sharing the same idea is
    /// intentionally idempotent because the user-facing metric is a list of
    /// ideas shared, rather than a raw number of share-sheet openings.
    static func recordIdeaShare(_ ideaID: Int) async {
        guard let userID = supabase.auth.currentUser?.id else { return }

        do {
            try await supabase
                .from("idea_shares")
                .insert(IdeaShareInsert(user_id: userID, idea_id: ideaID))
                .execute()
        } catch {
            // A duplicate share is expected and should never block the share
            // sheet. Other failures are also best-effort for this telemetry.
            print("Could not record idea share: \(error)")
        }
    }

    static func recordIdeaDeletion(_ ideaID: Int, localID: String) async {
        guard let userID = supabase.auth.currentUser?.id else { return }

        do {
            try await supabase
                .from("idea_deletions")
                .insert(
                    IdeaDeletionInsert(
                        user_id: userID,
                        idea_id: ideaID,
                        local_id: localID
                    )
                )
                .execute()
        } catch {
            print("Could not record idea deletion: \(error)")
        }
    }
}
