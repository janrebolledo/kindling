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
                    local_id: item.id,
                    idea_id: item.data.id,
                    user_id: userId!,
                    collection_id: newCollection.id

                )
            )
        }

        try await supabase.from("collection_items").insert(collectionItems)
            .execute()

    } catch {
        print(error)
    }

}
