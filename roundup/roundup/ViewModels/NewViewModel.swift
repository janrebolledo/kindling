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
}
