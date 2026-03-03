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
    @State private var homeVM = HomeViewModel()
    @State private var newVM = NewViewModel()
    @State private var pinsVM = PinsViewModel()
    @FocusState private var searchFocused: Bool
    @State private var placeholderIndex: Int = 0
    let searchPlaceholders = [
        "search", "cafes to study from...", "things to do...",
        "places to eat...",
    ]
    let generator = UIImpactFeedbackGenerator(style: .medium)

    private var selectedTabBinding: Binding<tab?> {
        Binding(
            get: { homeVM.selectedTab },
            set: { homeVM.selectedTab = $0 }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { homeVM.searchQuery },
            set: { homeVM.searchQuery = $0 }
        )
    }

    @ViewBuilder private var tabPill: some View {
        ZStack {
            VStack {}
                .frame(width: 76, height: 52)
                .glassEffect(.clear.interactive().tint(.white))
                .clipShape(RoundedRectangle(cornerRadius: 100))
                .offset(x: homeVM.animatedTab == .new ? -40 : 40)
            HStack {
                Button {
                    withAnimation(AnimationConstants.spring) {
                        homeVM.selectedTab = .new
                    }
                } label: {
                    VStack {
                        Image(systemName: "staroflife.fill")
                        Text("new")
                    }
                    .foregroundStyle(
                        homeVM.animatedTab == .new ? Color("hotpink") : .primary
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                Button {
                    withAnimation(AnimationConstants.spring) {
                        homeVM.selectedTab = .pins
                    }
                } label: {
                    VStack {
                        Image(systemName: "pin.fill")
                        Text("pins")
                    }
                    .foregroundStyle(
                        homeVM.animatedTab == .pins
                            ? Color("hotpink") : .primary
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
        Button(action: {
            Task {
                await newVM.saveCurrentCard()
                await pinsVM.fetchCards()
            }
        }) {
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
        .disabled(!newVM.canSave)
    }

    @ViewBuilder private var closeButton: some View {
        Button {
            homeVM.searchQuery = ""
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
                if homeVM.searchQuery.isEmpty {
                    Text(searchPlaceholders[placeholderIndex])
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .font(.neueMontreal(.regular, size: 14))
                        .allowsHitTesting(false)
                        .id(placeholderIndex)
                        .transition(.opacity)
                }
                TextField("", text: searchQueryBinding)
                    .focused($searchFocused)
                    .font(.neueMontreal(.regular, size: 14))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .frame(maxWidth: homeVM.isSearching ? .infinity : 180)
        .clipShape(RoundedRectangle(cornerRadius: 100))
        .glassEffect(.clear)
        .shadow(color: .primary.opacity(0.1), radius: 5)
        .animation(AnimationConstants.spring, value: homeVM.isSearching)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard homeVM.searchQuery.isEmpty else { continue }
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
                        NewView(viewModel: newVM)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(tab.new)

                    VStack {
                        PinsView(viewModel: pinsVM)
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(tab.pins)
                }
                .scrollTargetLayout()

            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: selectedTabBinding)
        }

        .onChange(of: homeVM.selectedTab) { _, newTab in
            homeVM.switchTab(newTab)
            generator.impactOccurred()
            if homeVM.isSearching {
                searchFocused = false
                homeVM.searchQuery = ""
            }
        }
        .onChange(of: searchFocused) { _, focused in
            withAnimation(AnimationConstants.spring) {
                homeVM.isSearching = focused
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
                    .frame(height: 150)
                    .allowsHitTesting(false)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(uiColor: UIColor.systemBackground).opacity(0),
                            Color(uiColor: UIColor.systemBackground).opacity(1),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .allowsHitTesting(false)

                    HStack(spacing: 12) {
                        if !homeVM.isSearching { tabPill }
                        if homeVM.animatedTab == .new && !homeVM.isSearching {
                            saveIdeaButton
                        }
                        if homeVM.animatedTab == .pins { searchBar }
                        if homeVM.isSearching { closeButton }
                    }
                    .padding(
                        .bottom, homeVM.keyboardHeight > 0 ? 16 : 64
                    )
                    .padding(.horizontal, 16)
                }
                Color(uiColor: UIColor.systemBackground)
                    .frame(height: homeVM.keyboardHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }
}
