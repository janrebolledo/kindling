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

                VStack {
                    VStack {
                        HStack {
                            Text("New Captures")
                                .font(.editorialNew(.regular, size: 24))
                            Text(
                                "\(viewModel.currentCardIndex + 1)/\(viewModel.newStoredCards.count)"
                            )
                        }
                    }
                    .padding(.top, 128)

                    IdeaView(
                        card: viewModel.newStoredCards[
                            viewModel.currentCardIndex
                        ],
                        function: { _ in await viewModel.fetchCards() }
                    )
                    .padding(.bottom, 128)
                }
            }
        }
        .task {
            await viewModel.fetchCards()
        }
    }
}
