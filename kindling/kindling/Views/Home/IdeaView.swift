//
//  IdeaView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/19/26.
//

import CoreLocation
import Observation
import os
import Photos
import Supabase
import SwiftUI
import UIKit

private let pillBackground = Color("raisedSurface")
private let destructiveRed = Color(red: 1.0, green: 56 / 255, blue: 60 / 255)

struct IdeaView: View {
    var card: CardData
    var placeDetails: GooglePlaceDetails?
    var etaString: String?
    var googlePlaceHours: GooglePlaceHours?
    var transportType: TransportType = .driving
    var function: (ItemWrapper?) async -> Void
    var allowsDeletion = true
    var isPreview = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localImage: UIImage?
    @State private var imageRequestToken = UUID()
    @State private var screenshotDate: Date?
    @State private var showQuickLook = false
    @State private var isDeletingFromCollection = false
    @State private var isDeletingFromDevice = false
    @State private var showShareSheet = false
    @State private var resolvedPlaceDetails: GooglePlaceDetails?
    @State private var resolvedGooglePlaceHours: GooglePlaceHours?
    @State private var polaroidRotation = Double.random(in: -6...6)

    private var venueTitle: String {
        placeDetails?.name ?? resolvedPlaceDetails?.name ?? card.ideas?.name ?? "Untitled"
    }

    private var resolvedPlace: GooglePlaceDetails? {
        placeDetails ?? resolvedPlaceDetails
    }

    private var placeHours: GooglePlaceHours? {
        googlePlaceHours ?? resolvedGooglePlaceHours
    }

    private var locationText: String {
        card.ideas?.locationTypeLabel ?? "saved place"
    }

    private var displayedHeroHeight: CGFloat {
        isPreview ? 150 : LayoutConstants.heroHeight
    }

    private var imageLoadID: String {
        "\(card.id)-\(card.local_id)-\(card.ideas?.media_url ?? "remote")"
    }

    private var googleMapsMediaURL: URL? {
        let value = resolvedPlace?.photoUrl ?? card.ideas?.media_url
        return value.flatMap(URL.init(string:))
    }

    var body: some View {
        ScrollView {
            // Hero image with gradient fade
            heroSection
                .background { SheetScrollOwnership() }

            // Title + share + status + highlights
            VStack(alignment: .leading, spacing: 0) {
                // Title row
                HStack(alignment: .center, spacing: 8) {
                    Text(venueTitle)
                        .font(.system(size: 32, weight: .medium))
                        .tracking(-0.8)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        let ideaID = card.ideas?.id ?? card.id
                        Task { await UserAnalyticsService.recordIdeaShare(ideaID) }
                        showShareSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("share")
                        }
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                // Status row
                if let status = placeHours?.status {
                    HStack(spacing: 8) {
                        Text(status.isOpen ? "Open" : "Closed").fontWeight(.medium)
                        Text(status.detail)
                    }
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.secondary)
                } else if card.ideas?.locationTypeLabel != nil || card.ideas?.duration != nil {
                    HStack(spacing: 8) {
                        if let locationType = card.ideas?.locationTypeLabel {
                            Text(locationType).fontWeight(.medium)
                        }
                        if let hrs = card.ideas?.duration {
                            Text(hrs)
                        }
                    }
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.secondary)
                }

            }
            .padding(.top, 6)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            // Highlights card
            if card.ideas?.description != nil || card.ideas?.name != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("highlights")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)
                    if let name = card.ideas?.name {
                        Text(name)
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(.primary)
                    }
                    if let description = card.ideas?.description {
                        Text(description)
                            .font(.system(size: 14, weight: .medium))
                            .tracking(-0.35)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }

            if let placeHours {
                VStack(alignment: .leading, spacing: 14) {
                    Text("hours")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(placeHours.rows) { row in
                            HStack(alignment: .top) {
                                Text(row.day)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(width: 127, alignment: .leading)
                                Text(row.hours)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let sourceURL = placeHours.sourceURL {
                        Link(destination: sourceURL) {
                            Text("Google Maps ↗")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }

            // Location + ETA row
            HStack {
                Text(locationText)
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: transportType.icon)
                    Text(etaString ?? "—")
                }
                .font(.system(size: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Map
            mapSection
                .padding(.horizontal, 13)
                .padding(.bottom, 48)
                .background { SheetScrollOwnership() }

            // Polaroid + saved info + actions
            savedSection
                .padding(.horizontal, 16)
                .padding(.bottom, 48)

            // Bottom action buttons
            VStack(spacing: 14) {
                Button {
                    // TODO: report issue
                } label: {
                    Label("Report an issue", systemImage: "exclamationmark.bubble.fill")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(pillBackground)
                .clipShape(Capsule())

                if allowsDeletion {
                    Button {
                        guard !isDeletingFromCollection else { return }
                        isDeletingFromCollection = true
                        Task {
                            await deleteFromCollection(deleteFromDevice: false)
                            isDeletingFromCollection = false
                        }
                    } label: {
                        Label("Delete from kindling", systemImage: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(isDeletingFromCollection ? .secondary : destructiveRed)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(pillBackground)
                    .clipShape(Capsule())
                    .disabled(isDeletingFromCollection)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 72)
        }
        .ignoresSafeArea()
        .task(id: imageLoadID) {
            let requestToken = UUID()
            imageRequestToken = requestToken
            localImage = nil
            screenshotDate = nil

            guard !card.local_id.isEmpty else { return }

            let result = PHAsset.fetchAssets(withLocalIdentifiers: [card.local_id], options: nil)
            screenshotDate = result.firstObject?.creationDate

            let loadedImage = try? await loadImage(from: card.local_id)
            guard !Task.isCancelled, imageRequestToken == requestToken else { return }

            localImage = loadedImage
        }
        .task(id: card.ideas?.place_id) {
            await resolvePlaceDetailsIfNeeded()
            resolvedGooglePlaceHours = resolvedPlace?.hours
        }
        .sheet(isPresented: $showShareSheet) {
            IdeaShareSheet(items: [shareURL])
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var heroSection: some View {
        GeometryReader { geometry in
            Group {
                if let url = googleMapsMediaURL {
                    let transaction = Transaction(
                        animation: reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.2)
                    )

                    AsyncImage(url: url, transaction: transaction) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        default:
                            if let localImage {
                                Image(uiImage: localImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                placeholderImage(geometry: geometry)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: displayedHeroHeight)
                    .clipped()
                } else if let localImage {
                    Image(uiImage: localImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: displayedHeroHeight)
                        .clipped()
                } else {
                    placeholderImage(geometry: geometry)
                }
            }
        }
        .frame(height: displayedHeroHeight)
        .clipShape(RoundedRectangle(cornerRadius: isPreview ? 20 : 28, style: .continuous))
        .padding(.horizontal, isPreview ? 0 : 16)
        .padding(.top, isPreview ? 0 : 16)
        .padding(.bottom, isPreview ? 8 : 16)
        .animation(
            reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.4, dampingFraction: 0.9),
            value: isPreview
        )
    }

    @ViewBuilder
    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            if let coordinate = resolvedPlace?.coordinate {
                GoogleMapView(
                    coordinate: coordinate,
                    title: venueTitle,
                    isInteractive: false
                )
                    .allowsHitTesting(false)
                    .frame(height: 203)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                Button {
                    if let url = resolvedPlace?.googleMapsUri.flatMap(URL.init(string:)) {
                        openURL(url)
                    }
                } label: {
                    Text("open in Maps ↗")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.25))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(19)
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 203)
            }

        }
        .frame(height: 203)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func resolvePlaceDetailsIfNeeded() async {
        guard placeDetails == nil, resolvedPlaceDetails == nil,
              let placeID = card.ideas?.place_id else { return }
        resolvedPlaceDetails = await GooglePlacesService.shared.details(for: placeID)
        resolvedGooglePlaceHours = resolvedPlaceDetails?.hours
    }

    private func resolveGooglePlaceHoursIfNeeded() async {
        guard placeHours == nil else {
            return
        }
        await resolvePlaceDetailsIfNeeded()
        resolvedGooglePlaceHours = resolvedPlace?.hours
    }

    @ViewBuilder
    private var savedSection: some View {
        VStack(alignment: .center, spacing: 16) {
            // Polaroid
            Group {
                if let localImage {
                    Image(uiImage: localImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 143, height: 143)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                } else {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 143, height: 143)
                }
            }
            .padding(8)
            .padding(.bottom, 24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            .rotationEffect(.degrees(polaroidRotation))
            .onTapGesture {
                if localImage != nil { showQuickLook = true }
            }

            // Saved on label
            VStack(spacing: 6) {
                Text("Saved on")
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(savedDateText)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // View + Delete pill buttons
            HStack(spacing: 8) {
                Button {
                    showQuickLook = true
                } label: {
                    Label("View", systemImage: "photo")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
                .background(pillBackground)
                .clipShape(Capsule())
                .disabled(localImage == nil)
                .sheet(isPresented: $showQuickLook) {
                    if let image = localImage {
                        ImagePreviewSheet(image: image)
                    }
                }

                if allowsDeletion {
                    Button {
                        guard !isDeletingFromDevice else { return }
                        isDeletingFromDevice = true
                        Task {
                            await deleteFromCollection(deleteFromDevice: true)
                            isDeletingFromDevice = false
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .tracking(-0.4)
                            .foregroundStyle(isDeletingFromDevice ? .secondary : destructiveRed)
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .background(pillBackground)
                    .clipShape(Capsule())
                    .disabled(isDeletingFromDevice)
                }
            }
        }
    }

    // MARK: - Helpers

    private var shareURL: URL {
        webBaseURL
            .appendingPathComponent("s")
            .appendingPathComponent("\(card.ideas?.id ?? card.id)")
    }

    private func deleteFromCollection(deleteFromDevice: Bool = false) async {
        do {
            try await supabase
                .from("collection_items")
                .delete()
                .eq("id", value: card.id)
                .execute()

            let ideaID = card.ideas?.id ?? card.id
            Task {
                await UserAnalyticsService.recordIdeaDeletion(
                    ideaID,
                    localID: card.local_id
                )
            }

            if deleteFromDevice {
                let fetchResult = PHAsset.fetchAssets(
                    withLocalIdentifiers: [card.local_id],
                    options: nil
                )
                if let asset = fetchResult.firstObject {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets([asset] as NSArray)
                    }
                }
            }

            dismiss()
            await function(card as? ItemWrapper)
        } catch {
            print("Error deleting: \(error)")
        }
    }

    private func placeholderImage(geometry: GeometryProxy) -> some View {
        Color.gray.opacity(0.2)
            .frame(width: geometry.size.width, height: displayedHeroHeight)
    }

    private var savedDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        if let date = screenshotDate {
            return formatter.string(from: date)
        }
        return "unknown"
    }
}

private struct IdeaShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

/// Keeps sheet dismiss attached to the idea scroller. The map would otherwise
/// steal the pan, so pulling down at the top rubber-bands instead of dragging
/// the sheet away.
///
/// This must stay scoped to the idea scroller. The idea view can be pushed into
/// the discovery sheet, whose presenting host also contains the home carousels.
/// Mutating sibling scroll views here leaves those carousels disabled after the
/// idea is dismissed.
private struct SheetScrollOwnership: UIViewRepresentable {
    func makeUIView(context: Context) -> SentinelView {
        SentinelView()
    }

    func updateUIView(_ uiView: SentinelView, context: Context) {}

    final class SentinelView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { self.claimPrimaryScroller() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            claimPrimaryScroller()
        }

        private func claimPrimaryScroller() {
            // GoogleMapView is non-interactive in this screen, so the parent
            // ScrollView retains ownership without reaching into map internals.
        }

    }
}

struct ImagePreviewSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var allowsPan = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnificationGesture)
                    .simultaneousGesture(panGesture, including: allowsPan ? .all : .none)
                    .onTapGesture(count: 2, perform: resetZoom)
                    .animation(.interactiveSpring, value: scale)
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview("Screenshot", image: Image(uiImage: image))
                    )
                }
            }
        }
        .interactiveDismissDisabled(allowsPan)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
                allowsPan = scale > 1
                if !allowsPan {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func resetZoom() {
        withAnimation(.spring) {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
            allowsPan = false
        }
    }
}
