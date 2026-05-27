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
            $0.buttonStyle(.glassProminent).tint(Color("hotpink"))
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
