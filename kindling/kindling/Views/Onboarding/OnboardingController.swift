//
//  OnboardingController.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//
import Photos
import UIKit

class ScreenshotManager {

    nonisolated init() {}

    // Request photo library access
    func requestPhotoLibraryAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        return (status == .authorized || status == .limited)
    }

    // Fetch all screenshots from the photo library
    nonisolated func fetchScreenshots() -> [PHAsset] {
        let fetchOptions = PHFetchOptions()

        // Filter for screenshots using mediaSubtypes
        fetchOptions.predicate = NSPredicate(
            format: "mediaSubtypes == %d",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )

        // Sort by creation date (newest first)
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let screenshots = PHAsset.fetchAssets(
            with: .image,
            options: fetchOptions
        )

        var screenshotArray: [PHAsset] = []
        screenshots.enumerateObjects { asset, _, _ in
            screenshotArray.append(asset)
        }

        return screenshotArray
    }

    // Load image from PHAsset
    nonisolated func loadImage(
        from asset: PHAsset,
        targetSize: CGSize = PHImageManagerMaximumSize,

    ) async throws -> (String, UIImage?) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: (asset.localIdentifier, image))
            }
        }
    }

    // Get screenshot metadata
    func getScreenshotInfo(from asset: PHAsset) -> [String: Any] {
        return [
            "creationDate": asset.creationDate ?? Date(),
            "modificationDate": asset.modificationDate ?? Date(),
            "pixelWidth": asset.pixelWidth,
            "pixelHeight": asset.pixelHeight,
            "localIdentifier": asset.localIdentifier,
        ]
    }
}

func loadImage(
    from id: String,
    targetSize: CGSize = PHImageManagerMaximumSize,

) async throws -> UIImage? {
    let fetchOptions = PHFetchOptions()
    let fetchResult = PHAsset.fetchAssets(
        withLocalIdentifiers: [id],
        options: fetchOptions
    )

    guard let asset = fetchResult.firstObject else {
        print("was unable to fetch asset :(")
        return nil
    }

    let options = PHImageRequestOptions()
    options.isSynchronous = false
    options.deliveryMode = .highQualityFormat

    return try await withCheckedThrowingContinuation { continuation in
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            continuation.resume(returning: image)
        }
    }
}
