//
//  PinsViewModel.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Observation
import Supabase

enum CategoryFilter: String, CaseIterable {
    case all = "all"
    case activities = "activities"
    case events = "events"
    case eats = "eats"
}

@Observable
class PinsViewModel {
    var collections: [CollectionWrapper] = []
    var collection: CollectionWrapper? = nil
    var selectedFilter: CategoryFilter = .all
    var isLoading: Bool = false

    var filteredItems: [CollectionItemWrapper] {
        guard selectedFilter != .all else {
            return collection?.collection_items ?? []
        }
        return (collection?.collection_items ?? []).filter {
            $0.ideas?.type?.lowercased() == selectedFilter.rawValue
        }
    }

    func fetchCards() async {
        do {
            collections =
                try await supabase
                .from("collections")
                .select("*, collection_items(*, ideas(*))").execute()
                .value
            collection = collections.first
        } catch {
            dump(error)
        }
    }
}
