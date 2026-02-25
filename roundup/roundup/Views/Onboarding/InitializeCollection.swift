//
//  InitializeCollection.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/8/26.
//

import Foundation
import Supabase

func InitializeCollection(items: [ItemWrapper]) async {
    do {
        let userId = supabase.auth.currentUser?.id

        let newCollection: collection = collection(
            id: Int.random(in: 0...100_000_000),
            name: "My List",
            emoji: "📁",
            user_id: userId ?? nil
        )

        try await supabase.from("collections").insert(newCollection).execute()

        var collectionItems = [collection_item]()

        for item in items {
            collectionItems.append(
                collection_item(
                    id: Int.random(in: 0...100_000_000),
                    created_at: nil,
                    local_id: item.local_id,
                    idea_id: (item.ideas?.id)!,
                    user_id: userId!,
                    collection_id: newCollection.id
                )
            )
        }

        try await supabase.from("collection_items").insert(collectionItems)
            .execute()

        if let userID = supabase.auth.currentUser?.id {
            let service = ParsedScreenshotsService()
            try? await service.syncToSupabase(userID: userID)
        }

    } catch {
        print(error)
    }

}

func InitializeCollectionItems(items: [ItemWrapper]) async {
    do {
        let userId = supabase.auth.currentUser?.id

        var collectionItems = [collection_item]()

        for item in items {
            collectionItems.append(
                collection_item(
                    id: Int.random(in: 0...100_000_000),
                    created_at: nil,
                    local_id: item.local_id,
                    idea_id: (item.ideas?.id)!,
                    user_id: userId!,
                    collection_id: nil
                )
            )
        }

        try await supabase.from("collection_items").insert(collectionItems)
            .execute()

        if let userID = supabase.auth.currentUser?.id {
            let service = ParsedScreenshotsService()
            try? await service.syncToSupabase(userID: userID)
        }

    } catch {
        print(error)
    }

}
