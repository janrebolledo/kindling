//
//  InitializeCollection.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/8/26.
//

import Foundation
import Supabase

// Insert payloads omit `id` so Supabase generates the identity primary key,
// avoiding the PK collisions the old Int.random ids caused.

private struct CollectionInsert: Encodable {
    let name: String
    let emoji: String
    let user_id: UUID
}

private struct CollectionItemInsert: Encodable {
    let local_id: String
    let idea_id: Int
    let user_id: UUID
    let collection_id: Int
    let highlights: String?
    let highlights_sources: [String]?
}

private struct CollectionItemRow: Decodable {
    let local_id: String
}

private struct CollectionRow: Decodable {
    let id: Int
    let name: String?
}

private struct CollectionNameUpdate: Encodable {
    let name: String
}

let defaultCollectionName = "nomnomnom"
private let legacyDefaultCollectionName = "My List"

/// Finds the user's default collection, creating it if needed, and returns its id.
/// Renames a leftover "My List" row to `nomnomnom` so existing accounts pick up the new name.
func defaultCollectionID(for userID: UUID) async throws -> Int {
    let existing: [CollectionRow] =
        try await supabase
        .from("collections")
        .select("id, name")
        .eq("user_id", value: userID)
        .execute()
        .value

    if let row = existing.first(where: { $0.name == defaultCollectionName }) {
        return row.id
    }

    if let row = existing.first(where: { $0.name == legacyDefaultCollectionName }) {
        try await supabase
            .from("collections")
            .update(CollectionNameUpdate(name: defaultCollectionName))
            .eq("id", value: row.id)
            .execute()
        return row.id
    }

    let created: CollectionRow =
        try await supabase
        .from("collections")
        .insert(CollectionInsert(name: defaultCollectionName, emoji: "📁", user_id: userID))
        .select("id, name")
        .single()
        .execute()
        .value
    return created.id
}

/// Renames a leftover "My List" collection to `nomnomnom` if one still exists.
func migrateLegacyDefaultCollectionName() async {
    guard let userID = supabase.auth.currentUser?.id else { return }
    do {
        let legacy: [CollectionRow] =
            try await supabase
            .from("collections")
            .select("id, name")
            .eq("user_id", value: userID)
            .eq("name", value: legacyDefaultCollectionName)
            .execute()
            .value

        for row in legacy {
            try await supabase
                .from("collections")
                .update(CollectionNameUpdate(name: defaultCollectionName))
                .eq("id", value: row.id)
                .execute()
        }
    } catch {
        dump(error)
    }
}

/// Persists the given draft items into the signed-in user's default collection.
/// Runs client-side: by this point the Supabase session is authenticated, so the
/// real user_id is attached and RLS enforces ownership. Ids are DB-generated.
func finalizeItems(_ items: [ItemWrapper]) async throws {
    guard !items.isEmpty else { return }
    guard let userID = supabase.auth.currentUser?.id else { return }

    let collectionID = try await defaultCollectionID(for: userID)

    let existing: [CollectionItemRow] = try await supabase
        .from("collection_items")
        .select("local_id")
        .eq("user_id", value: userID)
        .execute()
        .value
    let existingLocalIDs = Set(existing.map(\.local_id))

    let rows: [CollectionItemInsert] = items.filter { item in
        !existingLocalIDs.contains(item.local_id)
    }.map { item in
        CollectionItemInsert(
            local_id: item.local_id,
            idea_id: item.idea_id,
            user_id: userID,
            collection_id: collectionID,
            highlights: item.highlights,
            highlights_sources: item.highlights_sources
        )
    }
    guard !rows.isEmpty else { return }
    try await supabase.from("collection_items").insert(rows).execute()
}

/// Called at sign-up completion. Loads the cached onboarding drafts into the
/// user's collection, clears the draft cache, and syncs parsed IDs to Supabase.
func InitializeCollection(items: [ItemWrapper]) async {
    guard let userID = supabase.auth.currentUser?.id else { return }

    // Persist the handoff before the network insert. Auth state can make the
    // homepage visible while this function is still finalizing the rows.
    OnboardingHomeCache.save(items, for: userID)
    OnboardingHomeCache.clearPending()

    do {
        try await finalizeItems(items)
        OnboardingDraftCache.clear()

        let service = ParsedScreenshotsService(userID: userID)
        ParsedScreenshotsService.claimOnboardingIDs(for: userID)

        // Merge first so a returning user never loses parsed screenshot IDs
        // that exist on the server but not on this device.
        try await service.fetchAndMergeFromSupabase(userID: userID)
        try await service.syncToSupabase(userID: userID)
    } catch {
        print(error)
    }
}
