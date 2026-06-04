//
//  IdeaView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/19/26.
//

import CoreLocation
import MapKit
import Observation
import Photos
import Supabase
import SwiftUI

private let pillBackground = Color("raisedSurface")
private let destructiveRed = Color(red: 1.0, green: 56 / 255, blue: 60 / 255)

struct IdeaView: View {
    var card: CardData
    var mapItem: MKMapItem?
    var etaString: String?
    var function: (ItemWrapper?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localImage: UIImage?
    @State private var screenshotDate: Date?
    @State private var showQuickLook = false
    @State private var isDeletingFromCollection = false
    @State private var isDeletingFromDevice = false

    private var venueTitle: String {
        card.ideas?.venue ?? "Untitled"
    }

    private var locationText: String {
        (card.ideas?.location?.isEmpty ?? true)
            ? (card.ideas?.address ?? "—")
            : card.ideas?.location ?? "—"
    }

    var body: some View {
        ScrollView {
            // Hero image with gradient fade
            heroSection

            // Title + share + status + highlights
            VStack(alignment: .leading, spacing: 0) {
                // Title row
                HStack(alignment: .center, spacing: 8) {
                    Text(venueTitle)
                        .font(.system(size: 32, weight: .medium))
                        .tracking(-0.8)
                        .foregroundStyle(.primary)

                    Spacer()

                    ShareLink(
                        item: venueTitle,
                        subject: Text(venueTitle)
                    ) {
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
                if card.ideas?.location_type != nil || card.ideas?.duration != nil || card.ideas?.open_hours != nil {
                    HStack(spacing: 8) {
                        if let hours = card.ideas?.open_hours,
                           let status = resolveOpenStatus(from: hours) {
                            Text(status.isOpen ? "Open" : "Closed").fontWeight(.medium)
                            Text(status.detail)
                        } else {
                            if let locationType = card.ideas?.location_type {
                                Text(locationType).fontWeight(.medium)
                            }
                            if let hrs = card.ideas?.duration {
                                Text(hrs)
                            }
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

            // Location + ETA row
            HStack {
                Text(locationText)
                    .font(.system(size: 16))
                    .tracking(-0.4)
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "car.fill")
                    Text(etaString ?? "—")
                }
                .font(.system(size: 16))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(pillBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Map
            mapSection
                .padding(.horizontal, 13)
                .padding(.bottom, 48)

            // Hours
            if let hours = card.ideas?.open_hours, !hours.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("hours")
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.secondary)
                    ForEach(hours, id: \.self) { entry in
                        let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                        HStack(alignment: .top) {
                            Text(parts.first ?? entry)
                                .font(.system(size: 14, weight: .medium))
                                .tracking(-0.35)
                                .foregroundStyle(.primary)
                                .frame(width: 100, alignment: .leading)
                            Text(parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
                                .font(.system(size: 14))
                                .tracking(-0.35)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

            // Polaroid + saved info + actions
            savedSection
                .padding(.horizontal, 16)
                .padding(.bottom, 48)

            // Bottom action buttons
            VStack(spacing: 8) {
                Button {
                    // TODO: report issue
                } label: {
                    Label("Report an issue", systemImage: "exclamationmark.bubble.fill")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
                .background(pillBackground)
                .clipShape(Capsule())

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
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
                .background(pillBackground)
                .clipShape(Capsule())
                .disabled(isDeletingFromCollection)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 72)
        }
        .ignoresSafeArea()
        .onAppear {
            Task {
                localImage = try await loadImage(from: card.local_id)
                let result = PHAsset.fetchAssets(withLocalIdentifiers: [card.local_id], options: nil)
                screenshotDate = result.firstObject?.creationDate
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                Group {
                    if let mediaUrl = card.ideas?.media_url,
                        let url = URL(string: mediaUrl)
                    {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            default:
                                placeholderImage(geometry: geometry)
                            }
                        }
                        .frame(width: geometry.size.width, height: LayoutConstants.heroHeight)
                        .clipped()
                    } else if let localImage {
                        Image(uiImage: localImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: LayoutConstants.heroHeight)
                            .clipped()
                    } else {
                        placeholderImage(geometry: geometry)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.473),
                    .init(color: Color(uiColor: UIColor.systemBackground), location: 1.0),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: LayoutConstants.heroHeight)
            .frame(maxWidth: .infinity)
        }
        .frame(height: LayoutConstants.heroHeight)
    }

    @ViewBuilder
    private var mapSection: some View {
        ZStack(alignment: .bottom) {
            if let coordinate = mapItem?.location.coordinate {
                Map {
                    Marker(venueTitle, coordinate: coordinate)
                }
                .frame(height: 203)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                Button {
                    mapItem?.openInMaps()
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

            // "tap to view saved places nearby" bottom overlay
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        Color(uiColor: UIColor.systemBackground).opacity(0.75),
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial.opacity(0.3))

                Text("tap to view saved places nearby")
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 53)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 24,
                    bottomTrailingRadius: 24,
                    topTrailingRadius: 0
                )
            )
        }
        .frame(height: 203)
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
            .rotationEffect(.degrees(Double.random(in: -6...6)))
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
                        .padding(.horizontal, 16)
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
                        .padding(.horizontal, 16)
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
                .background(pillBackground)
                .clipShape(Capsule())
                .disabled(isDeletingFromDevice)
            }
        }
    }

    // MARK: - Helpers

    private func deleteFromCollection(deleteFromDevice: Bool = false) async {
        do {
            try await supabase
                .from("collection_items")
                .delete()
                .eq("id", value: card.id)
                .execute()

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
            .frame(width: geometry.size.width, height: LayoutConstants.heroHeight)
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

struct ImagePreviewSheet: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = max(1, lastScale * v) }
                            .onEnded { _ in lastScale = scale }
                            .simultaneously(with:
                                DragGesture()
                                    .onChanged { v in
                                        guard scale > 1 else { return }
                                        offset = CGSize(
                                            width: lastOffset.width + v.translation.width,
                                            height: lastOffset.height + v.translation.height
                                        )
                                    }
                                    .onEnded { _ in lastOffset = offset }
                            )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring) {
                            scale = 1; lastScale = 1
                            offset = .zero; lastOffset = .zero
                        }
                    }
                    .animation(.interactiveSpring, value: scale)
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Screenshot", image: Image(uiImage: image)))
                }
            }
        }
    }
}
