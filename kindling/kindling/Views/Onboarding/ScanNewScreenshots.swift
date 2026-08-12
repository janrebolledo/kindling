//
//  ScanNewScreenshots.swift
//  kindling
//
//  Searches the photo library for screenshots that haven't been parsed yet,
//  parses a small batch, saves the resulting ideas to the user's "My List"
//  collection, and records them as parsed both locally and in Supabase.
//

import Foundation
import Photos
import Supabase
import UIKit

/// Scans for new (unparsed) screenshots on app open and ingests a small batch.
/// - Parameter limit: maximum number of new screenshots to parse per call.
func scanForNewScreenshots(limit: Int = 5) async {
    await ScreenshotIndexingCoordinator.shared.scan(limit: limit)
}

/// Owns the indexing session so view lifecycle tasks and manual button taps
/// cannot select and process the same batch concurrently.
@MainActor
final class ScreenshotIndexingCoordinator {
    static let shared = ScreenshotIndexingCoordinator()

    private var currentScan: Task<Void, Never>?

    private init() {}

    func scan(limit: Int) async {
        if let currentScan {
            await currentScan.value
            return
        }

        let task = Task { await performScan(limit: limit) }
        currentScan = task
        await task.value
        currentScan = nil
    }

    private func performScan(limit: Int) async {
        guard let userID = supabase.auth.currentUser?.id else { return }

        let service = ParsedScreenshotsService(userID: userID)

        // Pull down any IDs parsed on other devices so we don't re-parse them.
        try? await service.fetchAndMergeFromSupabase(userID: userID)

        let manager = ScreenshotManager()
        let granted = await manager.requestPhotoLibraryAccess()
        guard granted else { return }

        let parsedIDs = service.loadLocalParsedIDs()
        let newScreenshots = manager.fetchScreenshots()
            .filter { !parsedIDs.contains($0.localIdentifier) }
            .prefix(limit)

        guard !newScreenshots.isEmpty else { return }
        let screenshots = Array(newScreenshots)
        print("Scanning \(screenshots.count) new screenshot(s)")

    // Load the underlying images.
        let images: [(String, UIImage?)] = await withTaskGroup(
            of: (String, UIImage?).self
        ) { group in
            for shot in screenshots {
                group.addTask {
                    (try? await manager.loadImage(from: shot))
                        ?? (shot.localIdentifier, nil)
                }
            }
            var results = [(String, UIImage?)]()
            for await result in group { results.append(result) }
            return results
        }
        .filter { $0.1 != nil }

    // Parse via the backend, collecting both ideas and explicit per-screenshot
    // acknowledgements. A missing acknowledgement remains eligible for retry.
        var cards: [ItemWrapper] = []
        var processedIDs = Set<String>()
        if !images.isEmpty {
            do {
                for try await event in uploadImagesStreaming(images: images) {
                    switch event {
                    case .idea(let item):
                        cards.append(item)
                    case .processed(let id):
                        processedIDs.insert(id)
                    }
                }
            } catch {
                dump(error)
                return
            }
        }

    // Persist server-side via /finalize (verifies our JWT, attaches user_id,
    // and saves the per-screenshot highlights onto the collection_items).
        if !cards.isEmpty {
            do {
                try await finalizeItems(cards)
            } catch {
                dump(error)
                return
            }
        }

    // Only mark backend-acknowledged screenshots after all produced cards have
    // been saved. Load/parse/save failures remain eligible for the next scan.
        service.markAsParsed(Array(processedIDs))
        try? await service.syncToSupabase(userID: userID)
    }
}
