//
//  NewViewModel.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Observation
import Supabase

@Observable
class NewViewModel {
    var newCards: [ItemWrapper] = []
    var newStoredCards: [CollectionItemWrapper] = []
    var currentCardIndex: Int = 0
    var screenshotManager = ScreenshotManager()
    var isLoading: Bool = false
    var error: Error? = nil

    var canSave: Bool { newStoredCards.count > 0 }

    func fetchCards() async {
        do {
            newStoredCards =
                try await supabase
                .from("collection_items")
                .select("*, ideas(*))")
                .is("collection_id", value: nil)
                .execute()
                .value
        } catch {
            self.error = error
            print(error)
        }
    }

    func saveCurrentCard() async {
        guard canSave, currentCardIndex < newStoredCards.count else { return }
        let currentCard = newStoredCards[currentCardIndex]

        struct CollectionRow: Decodable {
            let id: Int
        }
        struct UpdatePayload: Encodable {
            let collection_id: Int
        }

        do {
            let collections: [CollectionRow] = try await supabase
                .from("collections")
                .select("id")
                .execute()
                .value

            guard let firstCollection = collections.first else { return }

            try await supabase
                .from("collection_items")
                .update(UpdatePayload(collection_id: firstCollection.id))
                .eq("id", value: currentCard.id)
                .execute()

            await fetchCards()

            if currentCardIndex >= newStoredCards.count {
                currentCardIndex = max(0, newStoredCards.count - 1)
            }
        } catch {
            self.error = error
            print(error)
        }
    }
}
