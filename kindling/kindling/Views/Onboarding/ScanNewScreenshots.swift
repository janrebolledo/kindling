//
//  ScanNewScreenshots.swift
//  kindling
//
//  Owns screenshot discovery, progress, and indexing for the authenticated app.
//

import Foundation
import Observation
import Photos
import PhotosUI
import Supabase
import SwiftUI
import UIKit
import os

/// Owns the indexing session so automatic scans and account-screen actions
/// cannot select or process the same batch concurrently. It also owns the
/// progress snapshot shared by the home and account screens.
@MainActor
@Observable
final class ScreenshotIndexingController {
    static let shared = ScreenshotIndexingController()

    private static let screenshotsPerProcess = 5
    private static let processesPerTurn = 5
    private static let screenshotsPerTurn = screenshotsPerProcess * processesPerTurn

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "kindling",
        category: "ScreenshotIndexing"
    )

    var processedScreenshotCount = 0
    var totalScreenshotCount = 0
    var isProcessing = false
    var processingImageCount = 0
    var processedProcessingImageCount = 0
    var isBusy: Bool { currentOperation != nil }

    private enum OperationKind: Equatable {
        case automaticScan
        case selectedPhotos
        case progressRefresh
    }

    private var currentOperation: Task<Bool, Error>?
    private var currentOperationKind: OperationKind?

    private init() {}

    /// Runs the automatic app-open scan. The caller only coordinates the
    /// lifecycle; all indexing state remains in this controller.
    func scan() async -> Bool {
        let signpostID = KindlingProfiling.begin(KindlingProfiling.screenshotScan)
        defer {
            KindlingProfiling.end(KindlingProfiling.screenshotScan, id: signpostID)
        }

        if let currentOperation {
            let operationKind = currentOperationKind
            _ = try? await currentOperation.value
            if operationKind != .progressRefresh { return false }
        }

        let operation = Task<Bool, Error> { [weak self] in
            guard let self else { return false }
            return try await self.performAutomaticScan()
        }
        currentOperation = operation
        currentOperationKind = .automaticScan
        defer {
            currentOperation = nil
            currentOperationKind = nil
        }
        do {
            return try await operation.value
        } catch {
            Self.logger.error(
                "Automatic screenshot scan failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// Processes photos selected from the account screen.
    func processSelectedPhotos(_ items: [PhotosPickerItem]) async throws {
        guard !items.isEmpty else { return }
        if let currentOperation {
            let operationKind = currentOperationKind
            _ = try? await currentOperation.value
            if operationKind != .progressRefresh { return }
        }

        let operation = Task<Bool, Error> { [weak self] in
            guard let self else { return false }
            try await self.performSelectedPhotos(items)
            return true
        }
        currentOperation = operation
        currentOperationKind = .selectedPhotos
        defer {
            currentOperation = nil
            currentOperationKind = nil
        }
            _ = try await operation.value
    }

    /// Refreshes the account-screen progress without doing any work on the
    /// main actor. If indexing is already running, its final state is enough
    /// for the account screen and avoids a duplicate PhotoKit enumeration.
    func refreshProgress() async {
        if let currentOperation {
            _ = try? await currentOperation.value
            return
        }

        guard let userID = supabase.auth.currentUser?.id else { return }
        let operation = Task<Bool, Error> { [weak self] in
            guard let self else { return false }
            let progress = await Self.readProgress(for: userID)
            self.totalScreenshotCount = progress.total
            self.processedScreenshotCount = progress.processed
            return true
        }
        currentOperation = operation
        currentOperationKind = .progressRefresh
        defer {
            currentOperation = nil
            currentOperationKind = nil
        }
        _ = try? await operation.value
    }

    private func performAutomaticScan() async throws -> Bool {
        guard let userID = supabase.auth.currentUser?.id else { return false }

        isProcessing = true
        defer {
            isProcessing = false
            processingImageCount = 0
            processedProcessingImageCount = 0
        }

        let service = ParsedScreenshotsService(userID: userID)

        // Pull down any IDs parsed on other devices so we don't re-parse them.
        try? await service.fetchAndMergeFromSupabase(userID: userID)

        let manager = ScreenshotManager()
        guard await manager.requestPhotoLibraryAccess() else { return false }

        // A turn consists of five concurrent five-screenshot requests. Once a
        // turn completes, enumerate PhotoKit again so screenshots added while
        // processing are picked up in the next turn as well.
        var addedIdeas = false
        while true {
            // PhotoKit enumeration and image loading happen in the utility
            // task, keeping both the home screen and account screen responsive.
            let prepared = await Self.prepareAutomaticScan(
                limit: Self.screenshotsPerTurn,
                userID: userID
            )
            totalScreenshotCount = prepared.totalScreenshotCount
            processedScreenshotCount = prepared.processedScreenshotCount

            guard !prepared.images.isEmpty else { break }
            print("Scanning \(prepared.images.count) new screenshot(s)")

            processingImageCount = prepared.images.count
            processedProcessingImageCount = 0

            let result = await Self.processAutomaticTurn(images: prepared.images) {
                [weak self] processedCount in
                self?.processedProcessingImageCount += processedCount
            }

            // Persist server-side via /finalize (verifies our JWT, attaches
            // user_id, and saves the per-screenshot highlights).
            if !result.cards.isEmpty {
                try await finalizeItems(result.cards)
                addedIdeas = true
            }

            // Only mark backend-acknowledged screenshots after all produced
            // cards have been saved. Load/parse/save failures remain eligible
            // for retry in a later app-open scan.
            service.markAsParsed(Array(result.processedIDs))
            try? await service.syncToSupabase(userID: userID)
            processedScreenshotCount = min(
                totalScreenshotCount,
                processedScreenshotCount + result.processedIDs.count
            )

            // Do not spin forever when every request in a turn fails and no
            // screenshot receives a backend acknowledgement.
            guard !result.processedIDs.isEmpty else { break }
        }

        return addedIdeas
    }

    private static func processAutomaticTurn(
        images: [(String, UIImage?)],
        onBatchFinished: @escaping @MainActor (Int) -> Void
    ) async -> AutomaticTurnResult {
        let batches = stride(
            from: 0,
            to: images.count,
            by: screenshotsPerProcess
        ).map { index in
            Array(images[index..<min(index + screenshotsPerProcess, images.count)])
        }

        return await withTaskGroup(of: AutomaticBatchResult.self) { group in
            for batch in batches {
                group.addTask {
                    await processAutomaticBatch(images: batch)
                }
            }

            var cards: [ItemWrapper] = []
            var processedIDs = Set<String>()
            for await result in group {
                cards.append(contentsOf: result.cards)
                processedIDs.formUnion(result.processedIDs)
                onBatchFinished(result.processedIDs.count)
            }

            return AutomaticTurnResult(cards: cards, processedIDs: processedIDs)
        }
    }

    private static func processAutomaticBatch(
        images: [(String, UIImage?)]
    ) async -> AutomaticBatchResult {
        var cards: [ItemWrapper] = []
        var processedIDs = Set<String>()

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
            logger.error(
                "Automatic screenshot batch failed: \(String(describing: error), privacy: .public)"
            )
        }

        return AutomaticBatchResult(cards: cards, processedIDs: processedIDs)
    }

    private func performSelectedPhotos(_ items: [PhotosPickerItem]) async throws {
        guard let userID = supabase.auth.currentUser?.id else { return }

        isProcessing = true
        defer {
            isProcessing = false
            processingImageCount = 0
            processedProcessingImageCount = 0
        }

        let images = await Self.loadSelectedPhotos(from: items)
        guard !images.isEmpty else {
            throw ScreenshotIndexingError.noImages
        }

        processingImageCount = images.count
        processedProcessingImageCount = 0

        var cards: [ItemWrapper] = []
        var processedIDs = Set<String>()
        for try await event in uploadImagesStreaming(images: images) {
            switch event {
            case .idea(let item):
                cards.append(item)
            case .processed(let id):
                processedIDs.insert(id)
                processedProcessingImageCount = processedIDs.count
            }
        }

        // Save the processed ideas to the same default collection used by
        // automatic screenshot indexing.
        try await finalizeItems(cards)

        let service = ParsedScreenshotsService(userID: userID)
        service.markAsParsed(Array(processedIDs))
        try? await service.syncToSupabase(userID: userID)
        await refreshProgress(for: userID)
    }

    private func refreshProgress(for userID: UUID) async {
        let progress = await Self.readProgress(for: userID)
        totalScreenshotCount = progress.total
        processedScreenshotCount = progress.processed
    }

    private nonisolated static func readProgress(
        for userID: UUID
    ) async -> ScreenshotProgress {
        await Task.detached(priority: .utility) {
            let service = ParsedScreenshotsService(userID: userID)
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                return ScreenshotProgress(
                    total: 0,
                    processed: service.loadLocalParsedIDs().count
                )
            }

            let screenshots = ScreenshotManager().fetchScreenshots()
            let screenshotIDs = Set(screenshots.map(\.localIdentifier))
            let parsedIDs = service.loadLocalParsedIDs()
            return ScreenshotProgress(
                total: screenshots.count,
                processed: parsedIDs.intersection(screenshotIDs).count
            )
        }.value
    }

    private nonisolated static func prepareAutomaticScan(
        limit: Int,
        userID: UUID
    ) async -> PreparedAutomaticScan {
        await Task.detached(priority: .utility) {
            let service = ParsedScreenshotsService(userID: userID)
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            guard status == .authorized || status == .limited else {
                return PreparedAutomaticScan(
                    totalScreenshotCount: 0,
                    processedScreenshotCount: service.loadLocalParsedIDs().count,
                    images: []
                )
            }

            let manager = ScreenshotManager()
            let screenshots = manager.fetchScreenshots()
            let screenshotIDs = Set(screenshots.map(\.localIdentifier))
            let parsedIDs = service.loadLocalParsedIDs()
            let newScreenshots = screenshots
                .filter { !parsedIDs.contains($0.localIdentifier) }
                .prefix(limit)

            let images: [(String, UIImage?)] = await withTaskGroup(
                of: (String, UIImage?).self
            ) { group in
                for screenshot in newScreenshots {
                    group.addTask {
                        (try? await manager.loadImage(from: screenshot))
                            ?? (screenshot.localIdentifier, nil)
                    }
                }

                var results = [(String, UIImage?)]()
                for await result in group {
                    results.append(result)
                }
                return results
            }

            return PreparedAutomaticScan(
                totalScreenshotCount: screenshots.count,
                processedScreenshotCount: parsedIDs.intersection(screenshotIDs).count,
                images: images.filter { $0.1 != nil }
            )
        }.value
    }

    private nonisolated static func loadSelectedPhotos(
        from items: [PhotosPickerItem]
    ) async -> [(String, UIImage?)] {
        var images: [(String, UIImage?)] = []
        images.reserveCapacity(items.count)

        for item in items {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else { continue }

            images.append((item.itemIdentifier ?? UUID().uuidString, image))
        }

        return images
    }
}

private struct ScreenshotProgress: Sendable {
    let total: Int
    let processed: Int
}

private struct PreparedAutomaticScan {
    let totalScreenshotCount: Int
    let processedScreenshotCount: Int
    let images: [(String, UIImage?)]
}

private struct AutomaticBatchResult {
    let cards: [ItemWrapper]
    let processedIDs: Set<String>
}

private struct AutomaticTurnResult {
    let cards: [ItemWrapper]
    let processedIDs: Set<String>
}

enum ScreenshotIndexingError: LocalizedError {
    case noImages

    var errorDescription: String? {
        switch self {
        case .noImages:
            return "We couldn't load the selected photos. Please try again."
        }
    }
}
