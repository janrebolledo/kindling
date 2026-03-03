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

struct IdeaView: View {
    var card: CardData
    var function: (ItemWrapper?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mapItem: MKMapItem?
    @State private var localImage: UIImage?
    @State private var etaString: String?
    @State private var locationManager = LocationManager()

    private var address: String {
        (card.ideas?.address ?? card.ideas?.location ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var venueTitle: String {
        card.ideas?.venue ?? "Untitled"
    }

    var body: some View {

        ScrollView {

            ZStack(alignment: .bottom) {
                VStack {
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
                                    case .failure:
                                        placeholderImage(geometry: geometry)
                                    case .empty:
                                        placeholderImage(geometry: geometry)
                                    @unknown default:
                                        placeholderImage(geometry: geometry)
                                    }
                                }
                                .frame(
                                    width: geometry.size.width,
                                    height: LayoutConstants.heroHeight
                                )
                                .clipped()
                            } else if let localImage {
                                Image(uiImage: localImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(
                                        width: geometry.size.width,
                                        height: LayoutConstants.heroHeight
                                    )
                                    .clipped()
                            } else {
                                placeholderImage(geometry: geometry)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack {
                    VStack(alignment: .trailing) {
//                        Text("from @fff")
//                            .padding(12)
//                            .glassEffect(
//                                .clear.tint(
//                                    Color(uiColor: UIColor.systemBackground)
//                                        .opacity(0.5)
//                                )
//                            )
//                            .frame(
//                                maxWidth: .infinity,
//                                maxHeight: .infinity,
//                                alignment: .topTrailing
//                            )
                    }
                    .padding(32)
                    .frame(height: LayoutConstants.heroHeight * 0.6)
                    .frame(maxWidth: .infinity)
                    Spacer()

                    ZStack(alignment: .bottom) {
                        VariableBlurView(
                            maxBlurRadius: 10,
                            direction: .blurredBottomClearTop
                        )
                        .frame(maxHeight: .infinity)
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(0),
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(1),
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(1),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(alignment: .leading, spacing: 20) {
                            Spacer()

                            Text(venueTitle)
                                .font(.editorialNew(.regular, size: 32))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 12) {
                                if let locationType = card.ideas?.location_type {
                                    Text(locationType)
                                }
                                if let duration = card.ideas?.duration {
                                    if card.ideas?.location_type != nil {
                                        Text("•")
                                    }
                                    Text(duration)
                                }
                                if let pricing = card.ideas?.pricing {
                                    if card.ideas?.location_type != nil
                                        || card.ideas?.duration != nil
                                    {
                                        Text("•")
                                    }
                                    HStack(spacing: 0) {
                                        ForEach(
                                            0..<pricing,
                                            id: \.self
                                        ) { _ in Text("$") }
                                        ForEach(
                                            0..<max(0, 3 - pricing),
                                            id: \.self
                                        ) { _ in
                                            Text("$").foregroundStyle(
                                                .secondary
                                            )
                                        }
                                    }
                                }
                            }
                            .font(.neueMontreal(.regular, size: 16))
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: LayoutConstants.heroHeight * 0.4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 20)

            VStack(spacing: 24) {
                HStack {
                    Text(
                        (card.ideas?.location?.isEmpty ?? true)
                            ? (card.ideas?.address ?? "—")
                            : card.ideas?.location ?? "—"
                    )
                    Spacer()
                    Image(systemName: "car.fill")
                    Text(etaString ?? "—")
                }
                .font(.neueMontreal(.regular, size: 16))
                .padding(.horizontal, 24)
                .foregroundStyle(.secondary)

                if let coordinate = mapItem?.location.coordinate {
                    ZStack {
                        Map {
                            Marker(venueTitle, coordinate: coordinate)
                        }
                        Button("open in Apple Maps ↗") {
                            mapItem?.openInMaps()
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .glassEffect(
                            .clear.tint(
                                Color(uiColor: UIColor.systemBackground)
                                    .opacity(0.5)
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topTrailing
                        )
                        .padding(12)
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                } else {
                    VStack {
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                }

                HStack {

                    Group {
                        if let localImage {
                            Image(uiImage: localImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 93)
                        }
                    }
                    .frame(width: 93)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(.white, lineWidth: 8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 5)
                    .padding()
                    .rotationEffect(.degrees(Double.random(in: -6...6)))

                    VStack(alignment: .leading) {
                        Text("Saved From")
                            .foregroundStyle(.secondary)
                        Text(savedFromText)
                    }
                    .font(.neueMontreal(.regular, size: 16))

                }

                StyledButton(
                    title: "delete from collection & device",
                    systemName: "trash.fill"
                ) {
                    Task { await deleteFromCollection(deleteFromDevice: true) }
                }

                Button("delete from collection & keep on device") {
                    Task { await deleteFromCollection(deleteFromDevice: false) }
                }
                .foregroundStyle(.secondary)
                .font(.neueMontreal(.regular, size: 14))
                .padding(.bottom, 72)

            }
        }
        .ignoresSafeArea()
        .onAppear {
            locationManager.requestLocation()
            Task {
                localImage = try await loadImage(from: card.local_id)

                if !address.isEmpty,
                    let request = MKGeocodingRequest(addressString: address)
                {
                    do {
                        mapItem = try await request.mapItems.first
                    } catch {
                        print("error: \(error)")
                    }
                }

            }
        }
        .onChange(of: locationManager.location) { _, _ in
            Task { await fetchETA() }
        }
        .onChange(of: mapItem) { _, _ in
            Task { await fetchETA() }
        }

    }

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
        VStack { Color.gray.opacity(0.2) }
            .frame(
                width: geometry.size.width,
                height: LayoutConstants.heroHeight
            )
            .clipped()
    }

    private func fetchETA() async {
        guard let destination = mapItem, locationManager.location != nil else {
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return }
            let interval = route.expectedTravelTime
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            let formatted = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            await MainActor.run { etaString = formatted }
        } catch {
            await MainActor.run { etaString = nil }
        }
    }

    private var savedFromText: String {
        guard let created = card.ideas?.created_at, !created.isEmpty else {
            return "Screenshot from device"
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: created)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: created)
        }
        if date == nil {
            parser.formatOptions = [.withFullDate]
            date = parser.date(from: created)
        }
        guard let d = date else { return "Saved on \(created)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Saved on \(formatter.string(from: d))"
    }
}

private final class LocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        location = locations.last
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        location = nil
    }
}
