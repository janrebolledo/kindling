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

    @State var isSelected: Bool
    @State var label: String
    var action: () -> Void

    var body: some View {
        Button {
            isSelected.toggle()
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

struct PinsView: View {
    @State private var collections: [CollectionWrapper] = []
    @State private var collection: CollectionWrapper? = nil

    var body: some View {

        ScrollView {
            HStack {
                VStack(alignment: .leading, spacing: 16) {
                    Image("folder")
                        .resizable()
                        .frame(width: 64, height: 64)
                    HStack(spacing: 0) {
                        Text("the ").font(
                            .editorialNew(.regular, size: 24)
                        )
                        Text("list").font(
                            .editorialNew(.italic, size: 24)
                        )
                    }

                    Text(
                        "\(collection?.collection_items?.count ?? 0) ideas saved"
                    )
                    .foregroundStyle(.gray)
                    .font(
                        .neueMontreal(.regular, size: 16)
                    )
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
                    PillButton(isSelected: true, label: "all") {
                        print("items")
                    }
                    PillButton(isSelected: false, label: "activities") {
                        print("items")
                    }
                    PillButton(isSelected: false, label: "events") {
                        print("items")
                    }
                    PillButton(isSelected: false, label: "eats") {
                        print("items")
                    }
                }
                .padding(.leading, 16)
                .padding(.vertical, 24)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                if collection?.collection_items != nil {
                    ForEach((collection?.collection_items)!) { item in

                        Card(function: fetchCards, card: item)
                    }
                }
            }
            .padding()
            .padding(.bottom, 200)
            .task {
                await fetchCards(item: nil)
            }
        }
        .edgesIgnoringSafeArea(.top)
    }

    func fetchCards(item: ItemWrapper?) async {
        do {
            collections =
                try await supabase
                .from("collections")
                .select("*, collection_items(*, ideas(*))").execute()
                .value
            if collections.first != nil {
                collection = collections.first
            }

        } catch {
            dump(error)
        }
    }
}

struct NewView: View {
    @State private var screenshotManager = ScreenshotManager()
    @State private var newCards = [ItemWrapper]()
    @State private var newStoredCards = [CollectionItemWrapper]() {
        didSet {
            isSaveButtonDisabled = newStoredCards.count == 0
        }
    }
    @State private var currentCardIndex = 0
    @Binding var isSaveButtonDisabled: Bool

    var body: some View {

        VStack {
            if newStoredCards.count == 0 {

                Text("all clear 🫡")
                    .font(.editorialNew(.regular, size: 24))
                Text("you've cleaned up all of your screenshots")
                    .font(.neueMontreal(.regular, size: 14))

                Button("clear local storage") {
                    UserDefaults.standard.set(
                        [Any](),
                        forKey: "parsedScreenshotLocalIDs"
                    )
                }

                Button("parse more screenshots") {
                    Task {
                        var screenshots =
                            screenshotManager.fetchScreenshots()
                        let parsedScreenshotsService =
                            ParsedScreenshotsService()
                        let parsedIDs =
                            parsedScreenshotsService.loadLocalParsedIDs()
                        screenshots = screenshots.filter {
                            !parsedIDs.contains($0.localIdentifier)
                        }
                        screenshots =
                            Array(screenshots.prefix(5))
                        print("Parsing \(screenshots.count) screenshots")

                        let images: [(String, UIImage?)] =
                            await withTaskGroup(
                                of: (String, UIImage?).self
                            ) { group in
                                for screenshot in screenshots {
                                    group.addTask {

                                        return
                                            try! await screenshotManager
                                            .loadImage(from: screenshot)

                                    }
                                }

                                var results = [(String, UIImage?)]()
                                for await result in group {
                                    results.append(result)
                                }
                                return results
                            }

                        do {
                            newCards = []
                            for try await item in uploadImagesStreaming(
                                images: images
                            ) {
                                await MainActor.run {
                                    newCards.append(item)
                                }
                            }
                            await InitializeCollectionItems(items: newCards)
                            let uploadedIDs = images.map { $0.0 }
                            parsedScreenshotsService.markAsParsed(uploadedIDs)
                            await fetchCards(item: nil)
                        } catch {
                            print("upload error: \(error)")
                        }
                    }
                }
            } else {

                VStack {
                    VStack {
                        HStack {
                            Text("New Captures")
                                .font(.editorialNew(.regular, size: 24))
                            Text(
                                "\(currentCardIndex + 1)/\(newStoredCards.count)"
                            )
                        }
                    }
                    .padding(.top, 128)

                    IdeaView(
                        card: newStoredCards[currentCardIndex],
                        function: fetchCards
                    )
                    .padding(.bottom, 128)
                }
            }

        }.onAppear {
            Task {
                await fetchCards(item: nil)
            }
        }
    }

    func fetchCards(item: ItemWrapper?) async {
        do {
            newStoredCards =
                try await supabase
                .from("collection_items")
                .select("*, ideas(*))")
                .is("collection_id", value: nil)
                .execute()
                .value
            print(newStoredCards)
        } catch {
            print(error)
        }

    }
}

enum tab: String {
    case new
    case pins
}

struct ContentView: View {
    @State var currentTab: tab? = .new
    @State var animatedTab: tab? = .new
    @State private var searchQuery: String = ""
    @State private var isSearching: Bool = false
    @FocusState private var searchFocused: Bool
    @State private var placeholderIndex: Int = 0
    @State private var keyboardHeight: CGFloat = 0
    let searchPlaceholders = [
        "search", "cafes to study from...", "things to do...",
        "places to eat...",
    ]
    let generator = UIImpactFeedbackGenerator(style: .medium)
    @State private var isSaveButtonDisabled: Bool = false

    @ViewBuilder private var tabPill: some View {
        ZStack {
            VStack {}
                .frame(width: 76, height: 52)
                .glassEffect(.clear.interactive().tint(.white))
                .clipShape(RoundedRectangle(cornerRadius: 100))
                .offset(x: animatedTab == .new ? -40 : 40)
            HStack {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7))
                    { currentTab = .new }
                } label: {
                    VStack {
                        Image(systemName: "staroflife.fill")
                        Text("new")
                    }
                    .foregroundStyle(
                        animatedTab == .new ? Color("hotpink") : .primary
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7))
                    { currentTab = .pins }
                } label: {
                    VStack {
                        Image(systemName: "pin.fill")
                        Text("pins")
                    }
                    .foregroundStyle(
                        animatedTab == .pins ? Color("hotpink") : .primary
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
        .font(.neueMontreal(.regular, size: 14))
        .padding(4)
        .clipShape(RoundedRectangle(cornerRadius: 100))
        .glassEffect(.clear)
        .shadow(color: .primary.opacity(0.1), radius: 5)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private var saveIdeaButton: some View {
        Button(action: { print("hi") }) {
            HStack {
                Image(systemName: "plus")
                Text("save idea")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .font(.neueMontreal(.regular, size: 14))
            }
            .padding(.horizontal, 24)
        }
        .frame(width: 180)
        .frame(height: 60)
        .buttonStyle(.glassProminent)
        .tint(Color("hotpink"))
        .shadow(color: .primary.opacity(0.1), radius: 5)
        .transition(.scale.combined(with: .opacity))
        .disabled(isSaveButtonDisabled)
    }

    @ViewBuilder private var closeButton: some View {
        Button {
            searchQuery = ""
            searchFocused = false
        } label: {
            Image(systemName: "xmark")
                .padding(.vertical, 12)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: 64, maxHeight: 64)
        .buttonStyle(.glass)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary.opacity(0.5))
            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text(searchPlaceholders[placeholderIndex])
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .font(.neueMontreal(.regular, size: 14))
                        .allowsHitTesting(false)
                        .id(placeholderIndex)
                        .transition(.opacity)
                }
                TextField("", text: $searchQuery)
                    .focused($searchFocused)
                    .font(.neueMontreal(.regular, size: 14))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .frame(maxWidth: isSearching ? .infinity : 180)
        .clipShape(RoundedRectangle(cornerRadius: 100))
        .glassEffect(.clear)
        .shadow(color: .primary.opacity(0.1), radius: 5)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.7),
            value: isSearching
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard searchQuery.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.4)) {
                    placeholderIndex =
                        (placeholderIndex + 1) % searchPlaceholders.count
                }
            }
        }
    }

    var body: some View {

        VStack {

            ScrollView(.horizontal) {

                HStack(spacing: 0) {

                    VStack {
                        // new tab

                        NewView(isSaveButtonDisabled: $isSaveButtonDisabled)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(tab.new)
                    VStack {
                        // pins tab

                        PinsView()
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(tab.pins)
                }
                .scrollTargetLayout()

            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentTab)
        }

        .onChange(of: currentTab) { _, newTab in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                animatedTab = newTab
            }
            generator.impactOccurred()
            if isSearching {
                searchFocused = false
                searchQuery = ""
            }
        }
        .onChange(of: searchFocused) { _, focused in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isSearching = focused
            }
        }

        .overlay {
            VStack(spacing: 0) {

                Spacer()
                ZStack(alignment: .bottom) {
                    VariableBlurView(
                        maxBlurRadius: 20,
                        direction: .blurredBottomClearTop
                    )
                    .frame(height: 100)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(uiColor: UIColor.systemBackground).opacity(0),
                            Color(uiColor: UIColor.systemBackground).opacity(1),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity, maxHeight: 100)

                    HStack(spacing: 12) {
                        if !isSearching { tabPill }
                        if animatedTab == .new && !isSearching {
                            saveIdeaButton
                        }
                        if animatedTab == .pins { searchBar }
                        if isSearching { closeButton }
                    }
                    .padding(.bottom, keyboardHeight > 0 ? 16 : 64)
                    .padding(.horizontal, 16)
                }
                Color(uiColor: UIColor.systemBackground)
                    .frame(height: keyboardHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification
            )
        ) { notification in
            guard
                let frame = notification.userInfo?[
                    UIResponder.keyboardFrameEndUserInfoKey
                ] as? CGRect
            else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                keyboardHeight = frame.height
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification
            )
        ) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                keyboardHeight = 0
            }
        }
    }
}
