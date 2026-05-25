//
//  PinsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Supabase
import SwiftUI

struct PinsView: View {
    var viewModel: PinsViewModel

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
                        "\(viewModel.collection?.collection_items?.count ?? 0) ideas saved"
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
                    ForEach(CategoryFilter.allCases, id: \.self) { filter in
                        PillButton(
                            isSelected: viewModel.selectedFilter == filter,
                            label: filter.rawValue
                        ) {
                            viewModel.selectedFilter = filter
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
                ForEach(viewModel.filteredItems) { item in
                    Card(
                        function: { _ in await viewModel.fetchCards() },
                        card: item
                    )
                }
            }
            .padding()
            .padding(.bottom, 200)
        }
        .edgesIgnoringSafeArea(.top)
        .task {
            await viewModel.fetchCards()
        }
    }
}
