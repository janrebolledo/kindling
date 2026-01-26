//
//  OnboardingController.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//
import Photos
import UIKit

class ScreenshotManager {
    
    // Request photo library access
    func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized || status == .limited)
            }
        }
    }
    
    // Fetch all screenshots from the photo library
    func fetchScreenshots(completion: @escaping ([PHAsset]) -> Void) {
        let fetchOptions = PHFetchOptions()
        
        // Filter for screenshots using mediaSubtypes
        fetchOptions.predicate = NSPredicate(format: "mediaSubtypes == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        
        // Sort by creation date (newest first)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let screenshots = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var screenshotArray: [PHAsset] = []
        screenshots.enumerateObjects { asset, _, _ in
            screenshotArray.append(asset)
        }
        
        completion(screenshotArray)
    }
    
    // Load image from PHAsset
    func loadImage(from asset: PHAsset, targetSize: CGSize = PHImageManagerMaximumSize, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
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
            "localIdentifier": asset.localIdentifier
        ]
    }
}
