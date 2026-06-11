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

private struct CollectionRow: Decodable {
    let id: Int
}

/// Finds the user's "My List" collection, creating it if needed, and returns its id.
private func myListCollectionID(for userID: UUID) async throws -> Int {
    let existing: [CollectionRow] =
        try await supabase
        .from("collections")
        .select("id")
        .eq("user_id", value: userID)
        .eq("name", value: "My List")
        .limit(1)
        .execute()
        .value
    if let row = existing.first { return row.id }

    let created: CollectionRow =
        try await supabase
        .from("collections")
        .insert(CollectionInsert(name: "My List", emoji: "📁", user_id: userID))
        .select("id")
        .single()
        .execute()
        .value
    return created.id
}

/// Persists the given draft items into the signed-in user's "My List" collection.
/// Runs client-side: by this point the Supabase session is authenticated, so the
/// real user_id is attached and RLS enforces ownership. Ids are DB-generated.
func finalizeItems(_ items: [ItemWrapper]) async throws {
    guard !items.isEmpty else { return }
    guard let userID = supabase.auth.currentUser?.id else { return }

    let collectionID = try await myListCollectionID(for: userID)

    let rows: [CollectionItemInsert] = items.map { item in
        CollectionItemInsert(
            local_id: item.local_id,
            idea_id: item.idea_id,
            user_id: userID,
            collection_id: collectionID,
            highlights: item.highlights,
            highlights_sources: item.highlights_sources
        )
    }
    try await supabase.from("collection_items").insert(rows).execute()
}

/// Called at sign-up completion. Loads the cached onboarding drafts into the
/// user's collection, clears the draft cache, and syncs parsed IDs to Supabase.
func InitializeCollection(items: [ItemWrapper]) async {
    do {
        try await finalizeItems(items)
        OnboardingDraftCache.clear()

        if let userID = supabase.auth.currentUser?.id {
            let service = ParsedScreenshotsService()
            try? await service.syncToSupabase(userID: userID)
        }
    } catch {
        print(error)
    }
}
