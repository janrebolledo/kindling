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
    let collection_id: Int
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

                    Text("\(collection?.collection_items?.count ?? 0) ideas saved")
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

                        Card(card: item)
                        //                                .padding(.horizontal)
                    }
                }
            }
            .padding()
            .padding(.bottom, 200)
            .task {
                do {
                    print("try to get cards pls")
                    collections =
                        try await supabase
                        .from("collections")
                        .select("*, collection_items(*, ideas(*))").execute()
                        .value
                    collection = collections[0]

                } catch {
                    dump(error)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}

enum tab: String {
    case new
    case pins
}

struct ContentView: View {
    @State var currentTab: tab? = .new
    @State var animatedTab: tab? = .new
    let generator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {

        VStack {

            ScrollView(.horizontal) {

                HStack(spacing: 0) {

                    VStack {
                        // new tab

                        Color.blue
                    }
                    .containerRelativeFrame(.horizontal)
                    .id(tab.new)
                    VStack {
                        // pins tab

                        //                    Color.red
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
        }
        
        .overlay {
            VStack {

                Spacer()
                ZStack(alignment: .bottom) {
                    VariableBlurView(
                        maxBlurRadius: 20,
                        direction: .blurredBottomClearTop
                    )
                    .frame(height: 200)
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(uiColor: UIColor.systemBackground).opacity(0),
                            Color(uiColor: UIColor.systemBackground).opacity(1),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity, maxHeight: 200)

                    HStack(spacing: 16) {

                        ZStack {

                            VStack {
                            }
                            .frame(width: 76, height: 52)
                            .glassEffect(
                                .clear.interactive().tint(.white)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 100))
                            .offset(x: animatedTab == .new ? -40 : 40)

                            HStack {

                                Button {
                                    withAnimation(
                                        .spring(
                                            response: 0.4,
                                            dampingFraction: 0.7
                                        )
                                    ) {

                                        currentTab = .new
                                    }
                                } label: {
                                    VStack {
                                        Image(systemName: "staroflife.fill")
                                        Text("new")
                                    }
                                    .foregroundStyle(
                                        animatedTab == .new
                                            ? Color("hotpink") : .primary
                                    )
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)

                                Button {
                                    withAnimation(
                                        .spring(
                                            response: 0.4,
                                            dampingFraction: 0.7
                                        )
                                    ) {

                                        currentTab = .pins
                                    }
                                } label: {
                                    VStack {
                                        Image(systemName: "pin.fill")
                                        Text("pins")
                                    }
                                    .foregroundStyle(
                                        animatedTab == .pins
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
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 100).stroke(
//                                .white.opacity(0.4),
//                                lineWidth: 2
//                            )
//                        )
                        .clipShape(RoundedRectangle(cornerRadius: 100))
                        .glassEffect(.clear)
                        .shadow(radius: 5)

                        //                    search/button goes here

                        HStack {
                            Text("search")
                        }
                    }
                    .padding(.bottom, 64)
                }
            }
        }
        .ignoresSafeArea()
    }
}
