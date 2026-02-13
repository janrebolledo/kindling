//
//  ContentView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Foundation
internal import PostgREST
import Supabase
import SwiftUI

struct collectionWrapper: Decodable, Identifiable {
    let id: Int
    let created_at: String
    let name: String
    let emoji: String
    let user_id: UUID
    let collection_items: [collectionItemWrapper]?

}

struct collectionItemWrapper: Decodable, Identifiable {
    let id: Int
    let created_at: String
    let local_id: String
    let idea_id: Int
    let user_id: UUID
    let collection_id: Int
    let ideas: Item?
}

struct ContentView: View {
    @State private var collections: [collectionWrapper] = []

    var body: some View {

        ScrollView {
            ZStack(alignment: .leading) {

                Image("background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, minHeight: 350)
                    .clipped()

                LinearGradient(
                    gradient: Gradient(colors: [
                        .white.opacity(0),
                        .white.opacity(1),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(maxWidth: .infinity, maxHeight: 350)

                VStack(alignment: .leading) {
                    Text("captured").font(
                        .editorialNew(.italic, size: 24)
                    )

                    Text("32 screenshots saved")
                        .foregroundStyle(.gray)
                        .font(
                            .neueMontreal(.regular, size: 16)
                        )
                }
                .padding(.horizontal, 32)
            }
            .frame(height: 350)

            VStack {
                Button("hi") {
                    Task {
                        do {
                            try await supabase.auth.signOut()
                        }
                    }
                }
                ForEach(collections) { collection in
                    if (collection.collection_items?.count)! > 0 {

                        Text("\(collection.emoji) \(collection.name)")
                        if collection.collection_items != nil {
                            ForEach(collection.collection_items!) { item in

                                HomeCard(card: item)
                                //                                .padding(.horizontal)
                            }
                        }
                    }

                }
                .padding()

            }
            .task {
                do {
                    print("try to get cards pls")
                    collections =
                        try await supabase
                        .from("collections")
                        .select("*, collection_items(*, ideas(*))").execute()
                        .value
                    print(collections)

                } catch {
                    dump(error)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}

#Preview {
    ContentView()
}
