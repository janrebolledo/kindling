//
//  OnboardingPermissionsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 3/8/26.
//

import CoreLocation
import Photos
import SwiftUI

private enum PermissionStatus {
    case pending, granted, denied
}

private func requestLocationAccess() async -> Bool {
    let manager = CLLocationManager()
    let status = manager.authorizationStatus

    if status == .authorizedWhenInUse || status == .authorizedAlways {
        return true
    }
    if status == .denied || status == .restricted {
        return false
    }

    return await withCheckedContinuation { continuation in
        let delegate = LocationDelegate(continuation: continuation)
        manager.delegate = delegate
        manager.requestWhenInUseAuthorization()
        // Keep delegate alive until callback fires
        objc_setAssociatedObject(manager, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        continuation?.resume(returning: status == .authorizedWhenInUse || status == .authorizedAlways)
        continuation = nil
    }
}

struct OnboardingPermissionsView: View {
    @Binding var step: Int
    @Binding var cards: [ItemWrapper]
    @Binding var firstCardLoaded: Bool

    @State private var screenshotManager = ScreenshotManager()
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false

    @State private var networkStatus: PermissionStatus = .pending
    @State private var photosStatus: PermissionStatus = .pending
    @State private var locationStatus: PermissionStatus = .pending
    @State private var isProcessing: Bool = false
    @State private var spinAngle: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("something went wrong")
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    StyledButton(
                        title: "try again",
                        systemName: "arrow.clockwise"
                    ) {
                        errorMessage = nil
                        networkStatus = .pending
                        photosStatus = .pending
                        locationStatus = .pending
                        isProcessing = false
                        startUpload()
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Text(isProcessing ? "processing your screenshots" : "checking for permissions")
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut, value: isProcessing)

                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(label: "network", status: networkStatus)
                        permissionRow(label: "photos", status: photosStatus)
                        permissionRow(label: "location", status: locationStatus)
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
            startUpload()
        }
    }

    @ViewBuilder
    private func permissionRow(label: String, status: PermissionStatus) -> some View {
        HStack(spacing: 10) {
            Group {
                switch status {
                case .pending:
                    Image(systemName: "rays")
                        .rotationEffect(.degrees(spinAngle))
                case .granted:
                    Image(systemName: "checkmark.circle")
                case .denied:
                    Image(systemName: "xmark.circle")
                }
            }
            .frame(width: 20)

            Text(label)
        }
        .foregroundStyle(status == .pending ? .primary : .secondary)
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    private func startUpload() {
        isLoading = true
        Task {
            do {
                await MainActor.run { networkStatus = .granted }

                let granted = await screenshotManager.requestPhotoLibraryAccess()
                await MainActor.run {
                    photosStatus = granted ? .granted : .denied
                }
                guard granted else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "photos access is required to process your screenshots"
                    }
                    return
                }

                let locationGranted = await requestLocationAccess()
                await MainActor.run {
                    locationStatus = locationGranted ? .granted : .denied
                    isProcessing = true
                }

                var screenshots = screenshotManager.fetchScreenshots()
                let parsedScreenshotsService = ParsedScreenshotsService()
                let parsedIDs = parsedScreenshotsService.loadLocalParsedIDs()
                screenshots = screenshots.filter {
                    !parsedIDs.contains($0.localIdentifier)
                }
                screenshots = Array(screenshots.prefix(5))
                print("Parsing \(screenshots.count) screenshots")

                let images: [(String, UIImage?)] = await withTaskGroup(
                    of: (String, UIImage?).self
                ) { group in
                    for screenshot in screenshots {
                        group.addTask {
                            return try! await screenshotManager.loadImage(
                                from: screenshot
                            )
                        }
                    }
                    var results = [(String, UIImage?)]()
                    for await result in group {
                        results.append(result)
                    }
                    return results
                }

                await MainActor.run {
                    cards = []
                }

                for try await item in uploadImagesStreaming(images: images) {
                    await MainActor.run {
                        if !firstCardLoaded {
                            firstCardLoaded = true
                            step = 3
                        }
                        cards.append(item)
                    }
                }

                await MainActor.run {
                    if step == 2 {
                        step = 3
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    OnboardingPermissionsView(
        step: .constant(2),
        cards: .constant([]),
        firstCardLoaded: .constant(false)
    )
}
