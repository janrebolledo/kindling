//
//  ContentView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Foundation
import Photos
internal import PostgREST
import Supabase
import SwiftUI

struct CollectionWrapper: Decodable, Identifiable {
    let id: Int
    let created_at: String
    let name: String
    let emoji: String
    let user_id: UUID
    let collection_items: [CollectionItemWrapper]?
}

struct CollectionItemWrapper: Decodable, Identifiable, CardData {
    let id: Int
    let created_at: String
    let local_id: String
    let idea_id: Int
    let user_id: UUID
    let collection_id: Int?
    let ideas: Item?
}

/// A single idea can be created by several screenshots. Keep one row for the
/// UI while retaining every source screenshot for the idea detail view.
struct SavedIdea: Identifiable, CardData {
    let representative: CollectionItemWrapper
    let screenshots: [CollectionItemWrapper]

    var id: Int { representative.ideas?.id ?? representative.idea_id }
    var local_id: String { representative.local_id }
    var ideas: Item? { representative.ideas }
    var screenshotLocalIDs: [String] {
        screenshots.reduce(into: [String]()) { result, item in
            guard !item.local_id.isEmpty, !result.contains(item.local_id) else { return }
            result.append(item.local_id)
        }
    }
    var collectionItemIDs: [Int] {
        screenshots.reduce(into: [Int]()) { result, item in
            guard !result.contains(item.id) else { return }
            result.append(item.id)
        }
    }
}

func deduplicatedSavedIdeas(_ items: [CollectionItemWrapper]) -> [SavedIdea] {
    var grouped: [Int: [CollectionItemWrapper]] = [:]
    var order: [Int] = []

    for item in items {
        let ideaID = item.ideas?.id ?? item.idea_id
        if grouped[ideaID] == nil {
            order.append(ideaID)
        }
        grouped[ideaID, default: []].append(item)
    }

    return order.compactMap { ideaID in
        guard let screenshots = grouped[ideaID], let representative = screenshots.first else {
            return nil
        }
        return SavedIdea(representative: representative, screenshots: screenshots)
    }
}

struct PillButton: View {
    var isSelected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
        }
        .if(isSelected) {
            $0.buttonStyle(.glassProminent).tint(.pink)
        }
        .if(!isSelected) { $0.buttonStyle(.glass) }
    }
}

enum tab: String {
    case new
    case pins
}

struct ContentView: View {
    let searchPlaceholders = [
        "search", "cafes to study from...", "things to do...",
        "places to eat...",
    ]
    let generator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {

        VStack {
            PinsView()
        }

    }
}
