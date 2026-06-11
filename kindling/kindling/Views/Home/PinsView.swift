//
//  PinsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Supabase
import SwiftUI

private let figmaGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

struct PinsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State var collections: [CollectionWrapper] = []
    @State private var searchText: String = ""
    @State private var showAccount = false
    var isLoading: Bool = false

    // MARK: - Derived data

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matches(_ item: CollectionItemWrapper) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [item.ideas?.venue, item.ideas?.name, item.ideas?.location]
        return fields.contains { ($0?.lowercased().contains(query)) == true }
    }

    private func isEvent(_ item: CollectionItemWrapper) -> Bool {
        item.ideas?.type?.lowercased() == "event"
    }

    private func locationItems(for collection: CollectionWrapper) -> [CollectionItemWrapper] {
        (collection.collection_items ?? []).filter { !isEvent($0) && matches($0) }
    }

    private var eventItems: [CollectionItemWrapper] {
        var seen = Set<Int>()
        var result: [CollectionItemWrapper] = []
        for item in collections.flatMap({ $0.collection_items ?? [] })
        where isEvent(item) && matches(item) {
            let key = item.ideas?.id ?? item.idea_id
            if seen.insert(key).inserted { result.append(item) }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerContent

                ForEach(collections) { collection in
                    let items = locationItems(for: collection)
                    if !items.isEmpty {
                        section(title: "#\(collection.name)", items: items)
                    }
                }

                if !eventItems.isEmpty {
                    section(title: "events this week", items: eventItems)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) { gradient }
        }
        .scrollIndicators(.hidden)
        .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
        .task {
            await loadCollections()
            await scanForNewScreenshots()
            await loadCollections()
        }
    }

    private func loadCollections() async {
        do {
            collections =
                try await supabase
                .from("collections")
                .select("*, collection_items(*, ideas(*))").execute()
                .value
        } catch {
            dump(error)
        }
    }

    // MARK: - Header

    private var gradient: some View {
        Image(colorScheme == .dark ? "gradient dark" : "gradient light")
            .resizable()
            .scaledToFill()
            .frame(height: 380)
            .frame(maxWidth: .infinity)
            .clipped()
            .ignoresSafeArea(edges: .top)
    }

    private var headerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Image(colorScheme == .dark ? "kindling white" : "kindling black")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                Spacer()
                profilePill
            }

            Text("what's up, leo?")
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.6)
                .foregroundStyle(.primary)
                .padding(.top, 44)

            Text("here's the rundown of what you have saved.")
                .font(.system(size: 16))
                .tracking(-0.4)
                .foregroundStyle(.primary)
                .padding(.top, 8)

            searchBar
                .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var profilePill: some View {
        Button {
            showAccount = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 13))
                Text("jan")
                    .font(.system(size: 16))
                    .tracking(-0.4)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .tint(.primary)
        .sheet(isPresented: $showAccount) {
            AccountView()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary)
            TextField(
                "",
                text: $searchText,
                prompt: Text("cozy cafes to study from...").foregroundColor(figmaGray)
            )
            .tint(.primary)
            .foregroundStyle(.primary)
        }
        .font(.system(size: 16))
        .tracking(-0.4)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
    }

    // MARK: - Section

    private func section(title: String, items: [CollectionItemWrapper]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(figmaGray)
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        Card(card: item)
                            .frame(width: 300)
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
    }
}
