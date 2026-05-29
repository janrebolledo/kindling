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

// MARK: - Sample card model

private struct SampleCard: Identifiable {
    let id = UUID()
    let day: String
    let title: String
    let subtitle: String
    let detail: String
    let topColors: [Color]
    let cardBackground: Color
}

private let sampleCards: [SampleCard] = [
    SampleCard(
        day: "Saturday",
        title: "The Garage Sale",
        subtitle: "Fullerton, CA  •  🚗 15 min",
        detail: "$12.50 Tickets",
        topColors: [Color(red: 0.62, green: 0.50, blue: 0.38), Color(red: 0.44, green: 0.35, blue: 0.27)],
        cardBackground: Color(red: 248/255, green: 246/255, blue: 240/255)
    ),
    SampleCard(
        day: "Thursday",
        title: "Bolero Night",
        subtitle: "Café Tondo, Los Angeles, CA",
        detail: "See details",
        topColors: [Color(red: 0.58, green: 0.40, blue: 0.32), Color(red: 0.40, green: 0.28, blue: 0.22)],
        cardBackground: Color(red: 248/255, green: 245/255, blue: 242/255)
    ),
    SampleCard(
        day: "Thursday",
        title: "Jazz Trio",
        subtitle: "The Night Owl, Fullerton, CA",
        detail: "Free",
        topColors: [Color(red: 0.45, green: 0.50, blue: 0.62), Color(red: 0.32, green: 0.36, blue: 0.48)],
        cardBackground: Color(red: 247/255, green: 244/255, blue: 243/255)
    ),
]

// MARK: - Event card

private struct SampleEventCard: View {
    let card: SampleCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo area
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: card.topColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 150)

                // Day pill
                Text(card.day)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.35)
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .padding(10)
            }

            // Text content
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.6)
                    .foregroundColor(.black)

                Text(card.subtitle)
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundColor(.black)

                Text(card.detail)
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundColor(.black)
                    .opacity(0.5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card.cardBackground)
        }
        .frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20))
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

            VStack(spacing: 0) {
                // Card carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sampleCards) { card in
                            SampleEventCard(card: card)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 271)
                .padding(.top, 16)

                if let error = errorMessage {
                    errorSection(error: error)
                } else {
                    mainContent
                }

                Spacer()

                legalText
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                spinAngle = 360
            }
            startUpload()
        }
    }

    // MARK: - Subviews

    private var mainContent: some View {
        VStack(spacing: 0) {
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
            .padding(.top, 32)

            // Permission rows
            VStack(spacing: 20) {
                permissionRow(label: "Photos", status: photosStatus)
                permissionRow(label: "Network", status: networkStatus)
                permissionRow(label: "Location", status: locationStatus)
            }
            .padding(.top, 32)
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
                    step = 3
                }

                for try await item in uploadImagesStreaming(images: images) {
                    await MainActor.run {
                        cards.append(item)
                    }
                }

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

