//
//  OnboardingPermissionsView.swift
//  roundup
//
//  Created by Jan Rebolledo on 3/8/26.
//

import CoreLocation
import Photos
import Supabase
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

// MARK: - Main view

struct OnboardingPermissionsView: View {
    @Binding var step: Int
    @Binding var cards: [ItemWrapper]
    @Binding var screenshotImages: [UIImage]
    @Binding var totalScreenshotCount: Int
    @Binding var totalSizeGB: Double
    @Binding var isProcessing: Bool

    @State private var screenshotManager = ScreenshotManager()
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false

    @State private var networkStatus: PermissionStatus = .pending
    @State private var photosStatus: PermissionStatus = .pending
    @State private var locationStatus: PermissionStatus = .pending
    @State private var spinAngle: Double = 0
    @State private var showcaseCards: [ItemWrapper] = []

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            // Warm gradient at top (extends under the safe area header)
            Image(colorScheme == .dark ? "gradient dark" : "gradient light")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                OnboardingCardCarousel(cards: showcaseCards)
                .frame(height: 271)
                .padding(.top, 16)
                .padding(.horizontal, -48)

                if let error = errorMessage {
                    errorSection(error: error)
                } else {
                    mainContent
                }

                Spacer()

                legalText
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 48)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
            Task { await loadShowcaseCards() }
            startUpload()
        }
    }

    // MARK: - Subviews

    private var mainContent: some View {
        VStack(spacing: 24) {
            // Title: "add your gallery / to start kindling"
            VStack(spacing: 2) {
                Text("add your gallery")
                    .font(.system(size: 36, weight: .medium))
                    .tracking(-0.9)
                    .foregroundColor(.primary)

                HStack(spacing: 10) {
                    Text("to start")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-0.9)
                        .foregroundColor(.primary)
                    Image(colorScheme == .dark ? "kindling white" : "kindling black")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 30)
                }
            }
            .multilineTextAlignment(.center)

            // Permission rows
            VStack(spacing: 20) {
                permissionRow(label: "Photos", status: photosStatus)
                permissionRow(label: "Network", status: networkStatus)
                permissionRow(label: "Location", status: locationStatus)
            }
        }
    }

    @ViewBuilder
    private func errorSection(error: String) -> some View {
        VStack(spacing: 20) {
            Text("something went wrong")
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.6)
                .foregroundColor(.primary)
                .padding(.top, 32)

            Text(error)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            StyledButton(title: "try again", systemName: "arrow.clockwise") {
                errorMessage = nil
                networkStatus = .pending
                photosStatus = .pending
                locationStatus = .pending
                isProcessing = false
                startUpload()
            }
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
                    Image(systemName: "checkmark")
                case .denied:
                    Image(systemName: "xmark")
                }
            }
            .frame(width: 24)

            Text(label)
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.24)
        }
        .foregroundColor(.primary)
        .opacity(status == .granted ? 0.5 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: status)
    }

    private var legalText: some View {
        Text("By continuing, you agree to kindling's \(Text("Terms & Conditions").underline()) and acknowledge the \(Text("Privacy Policy").underline()).")
            .font(.system(size: 12))
            .foregroundColor(Color(red: 142/255, green: 142/255, blue: 147/255))
            .multilineTextAlignment(.center)
            .tracking(-0.12)
    }

    // MARK: - Logic (unchanged)

    private func loadShowcaseCards() async {
        do {
            let ideas: [Item] =
                try await supabase
                .from("ideas")
                .select()
                .limit(50)
                .execute()
                .value

            let candidates = ideas.filter {
                $0.media_url != nil && $0.venue != nil
            }
            let selected = Array(candidates.shuffled().prefix(8))
            showcaseCards = selected.map { idea in
                ItemWrapper(
                    id: idea.id,
                    local_id: "",
                    idea_id: idea.id,
                    highlights: nil,
                    highlights_sources: nil,
                    ideas: idea
                )
            }
        } catch {
            print("Unable to load onboarding showcase cards: \(error)")
        }
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
                }

                var allScreenshots = screenshotManager.fetchScreenshots()
                let totalCount = allScreenshots.count
                let parsedScreenshotsService = ParsedScreenshotsService()
                let parsedIDs = parsedScreenshotsService.loadLocalParsedIDs()
                allScreenshots = allScreenshots.filter { !parsedIDs.contains($0.localIdentifier) }
                let screenshots = Array(allScreenshots.prefix(5))
                print("Parsing \(screenshots.count) screenshots")

                let images: [(String, UIImage?)] = await withTaskGroup(of: (String, UIImage?).self) { group in
                    for screenshot in screenshots {
                        group.addTask {
                            return try! await screenshotManager.loadImage(from: screenshot)
                        }
                    }
                    var results = [(String, UIImage?)]()
                    for await result in group { results.append(result) }
                    return results
                }

                let uiImages = images.compactMap { $0.1 }
                await MainActor.run {
                    screenshotImages = uiImages
                    totalScreenshotCount = totalCount
                    totalSizeGB = Double(totalCount) * 3.5 / 1024
                    cards = []
                    isProcessing = true
                    withAnimation(.easeInOut(duration: 0.35)) { step = 3 }
                }

                var processedIDs = Set<String>()
                for try await event in uploadImagesStreaming(images: images) {
                    switch event {
                    case .idea(let item):
                        await MainActor.run {
                            cards.append(item)
                        }
                    case .processed(let id):
                        processedIDs.insert(id)
                    }
                }

                // Cache the enriched drafts locally so the user's items are ready
                // on next launch if they close the app before signing up.
                await MainActor.run {
                    OnboardingDraftCache.save(cards)
                }

                // Only retire screenshots explicitly acknowledged by the backend.
                parsedScreenshotsService.markAsParsed(Array(processedIDs))

                await MainActor.run {
                    isProcessing = false
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
        screenshotImages: .constant([]),
        totalScreenshotCount: .constant(0),
        totalSizeGB: .constant(0),
        isProcessing: .constant(false)
    )
}
