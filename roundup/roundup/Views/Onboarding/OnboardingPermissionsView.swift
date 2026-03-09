//
//  OnboardingPermissionsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 3/8/26.
//

import Photos
import SwiftUI

private enum PermissionStatus {
    case pending, granted, denied
}

struct OnboardingPermissionsView: View {
    @Binding var step: Int
    @Binding var cards: [ItemWrapper]
    @Binding var screenshotCount: Int
    @Binding var firstCardLoaded: Bool

    @State private var screenshotManager = ScreenshotManager()
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false

    @State private var networkStatus: PermissionStatus = .pending
    @State private var photosStatus: PermissionStatus = .pending
    @State private var isProcessing: Bool = false
    @State private var spinAngle: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("something went wrong")
                        .font(.editorialNew(.italic, size: 24))
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
                        isProcessing = false
                        startUpload()
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Text(isProcessing ? "processing your screenshots" : "checking for permissions")
                        .font(.neueMontreal(.regular, size: 14))
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut, value: isProcessing)

                    VStack(alignment: .leading, spacing: 12) {
                        permissionRow(label: "network", status: networkStatus)
                        permissionRow(label: "photos", status: photosStatus)
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
                .font(.neueMontreal(.regular, size: 24))
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

                await MainActor.run { isProcessing = true }

                var screenshots = screenshotManager.fetchScreenshots()
                let parsedScreenshotsService = ParsedScreenshotsService()
                let parsedIDs = parsedScreenshotsService.loadLocalParsedIDs()
                screenshots = screenshots.filter {
                    !parsedIDs.contains($0.localIdentifier)
                }
                await MainActor.run { screenshotCount = screenshots.count }
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
                    step = 3
                }

                for try await item in uploadImagesStreaming(images: images) {
                    await MainActor.run {
                        if !firstCardLoaded {
                            firstCardLoaded = true
                            step = 4
                        }
                        cards.append(item)
                    }
                }

                await MainActor.run {
                    if step == 3 {
                        step = 4
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
        screenshotCount: .constant(0),
        firstCardLoaded: .constant(false)
    )
}
