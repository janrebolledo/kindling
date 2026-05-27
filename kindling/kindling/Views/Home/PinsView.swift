//
//  PinsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Supabase
import SwiftUI

struct PinsView: View {
    @State var collections: [CollectionWrapper] = []
    @State var collection: CollectionWrapper? = nil
    @State var selectedFilter: CategoryFilter = .all
    var isLoading: Bool = false

    var filteredItems: [CollectionItemWrapper] {
        guard selectedFilter != .all else {
            return collection?.collection_items ?? []
        }
        return (collection?.collection_items ?? []).filter {
            $0.ideas?.type?.lowercased() == selectedFilter.rawValue
        }
    }

    var body: some View {
        ScrollView {
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    Image("folder")
                        .resizable()
                        .frame(width: 64, height: 64)
                    HStack(spacing: 0) {
                        Text("the ")
                        Text("list")
                    }

                    Text(
                        "\(collection?.collection_items?.count ?? 0) ideas saved"
                    )
                    .foregroundStyle(.gray)
                }
                Spacer()
                Button("", systemImage: "xmark") {
                    Task {
                        do {
                            try await supabase.auth.signOut()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 128)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CategoryFilter.allCases, id: \.self) { filter in
                        PillButton(
                            isSelected: selectedFilter == filter,
                            label: filter.rawValue
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.vertical, 24)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(filteredItems) { item in
                    Card(
                        card: item
                    )
                }
            }
            .padding()
            .padding(.bottom, 200)
        }
        .edgesIgnoringSafeArea(.top)
        .task {
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
}
