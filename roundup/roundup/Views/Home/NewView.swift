//
//  NewView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Photos
import SwiftUI

struct NewView: View {
    var viewModel: NewViewModel

    var body: some View {
        VStack {
            if viewModel.newStoredCards.count == 0 {

                Text("all clear 🫡")
                    .font(.editorialNew(.regular, size: 24))
                    .padding(.bottom, 16)
                Text("you've cleaned up all of your screenshots")
                    .font(.neueMontreal(.regular, size: 14))

                Button("parse more screenshots") {
                    Task {
                        var screenshots =
                            viewModel.screenshotManager.fetchScreenshots()
                        let parsedScreenshotsService =
                            ParsedScreenshotsService()
                        let parsedIDs =
                            parsedScreenshotsService.loadLocalParsedIDs()
                        screenshots = screenshots.filter {
                            !parsedIDs.contains($0.localIdentifier)
                        }
                        screenshots = Array(screenshots.prefix(5))
                        print("Parsing \(screenshots.count) screenshots")

                        let images: [(String, UIImage?)] =
                            await withTaskGroup(
                                of: (String, UIImage?).self
                            ) { group in
                                for screenshot in screenshots {
                                    group.addTask {
                                        return
                                            try! await viewModel
                                            .screenshotManager
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
                            viewModel.newCards = []
                            for try await item in uploadImagesStreaming(
                                images: images
                            ) {
                                await MainActor.run {
                                    viewModel.newCards.append(item)
                                }
                            }
                            await InitializeCollectionItems(
                                items: viewModel.newCards
                            )
                            let uploadedIDs = images.map { $0.0 }
                            parsedScreenshotsService.markAsParsed(uploadedIDs)
                            await viewModel.fetchCards()
                        } catch {
                            print("upload error: \(error)")
                        }
                    }
                }
            } else {

                ZStack(alignment: .top) {

                    IdeaView(
                        card: viewModel.newStoredCards[
                            viewModel.currentCardIndex
                        ],
                        function: { _ in viewModel.advanceToNextCard() }
                    )
                    .id(viewModel.newStoredCards[viewModel.currentCardIndex].id)
                    .padding(.top, 100)
                    .padding(.bottom, 128)

                    ZStack(alignment: .top) {
                        Color(UIColor.systemBackground).frame(
                            maxWidth: .infinity,
                            maxHeight: 100
                        )

                        VariableBlurView(
                            maxBlurRadius: 5,
                            direction: .blurredTopClearBottom
                        )
                        .frame(height: 100)
                        .allowsHitTesting(false)
                        .padding(.top, 100)
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(1),
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(0),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .allowsHitTesting(false)
                        .padding(.top, 100)
                        VStack {
                            HStack {
                                Text("New Captures")
                                    .font(.editorialNew(.regular, size: 24))
                                Spacer()
                                Text(
                                    "\(viewModel.currentCardIndex + 1)/\(viewModel.sessionTotal)"
                                )
                                .font(.neueMontreal(.regular, size: 12))
                            }
                            HStack(spacing: 4) {
                                ForEach(
                                    0..<viewModel.sessionTotal,
                                    id: \.self
                                ) { index in
                                    Color.primary
                                        .frame(
                                            maxWidth: index
                                                == viewModel.currentCardIndex
                                            ? .infinity : 50,
                                            maxHeight: 4
                                        )
                                        .clipShape(.capsule)
                                        .opacity(
                                            index == viewModel.currentCardIndex
                                                ? 1 : 0.5
                                        )
                                        .animation(AnimationConstants.spring, value: viewModel.currentCardIndex)
                                }
                            }
                        }
                        .padding(.top, 100)
                        .padding(.horizontal, 24)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
        }
        .task {
            await viewModel.fetchCards()
        }
    }
}
