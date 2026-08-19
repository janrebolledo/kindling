//
//  Card.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/23/26.
//
import CoreLocation
import MapKit
import SwiftUI

struct Card: View {
    @State var image: UIImage? = nil
    @State var sheetPresented: Bool = false
    @State private var mapItem: MKMapItem?
    @State private var etaString: String?
    @State private var locationManager = CardLocationManager()
    @State private var isNearViewport = false
    @Environment(UserSettings.self) private var userSettings
    @Environment(DirectionsCache.self) private var directionsCache

    private let directionsPreloadCount = 2

    var function: ((ItemWrapper?) async -> Void)?
    var card: CardData
    var mapName: String? = nil
    var loadsMapData = true
    var allowsDetailPresentation = true
    var allowsDeletion = true
    var animatesImageLoading = false

    private var venueTitle: String {
        mapName ?? mapItem?.name ?? card.ideas?.name ?? "Untitled"
    }

    private var isEvent: Bool {
        card.ideas?.type?.lowercased() == "event"
    }

    private var eventDayString: String? {
        guard let dateStr = card.ideas?.date, !dateStr.isEmpty else { return nil }
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEEE"
        for fmt in ["yyyy-MM-dd", "MM/dd/yyyy", "MMMM d, yyyy", "MMM d, yyyy"] {
            let parser = DateFormatter()
            parser.dateFormat = fmt
            if let date = parser.date(from: dateStr) {
                return dayFmt.string(from: date)
            }
        }
        return dateStr
    }

    var body: some View {
        Group {
            if isEvent { eventCard } else { locationCard }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            updateViewportProximity(frame)
        }
        .onAppear {
            applyCachedDirections()
            Task {
                if card.ideas?.media_url == nil, !card.local_id.isEmpty {
                    let loadedImage = try await loadImage(from: card.local_id)
                    if animatesImageLoading {
                        withAnimation(.easeOut(duration: 0.2)) {
                            image = loadedImage
                        }
                    } else {
                        image = loadedImage
                    }
                }
            }
        }
        .task(id: directionsTaskID) {
            guard shouldFetchDirections else { return }
            applyCachedDirections()
            if mapItem != nil, etaString != nil { return }
            locationManager.requestLocation()
            await fetchMapData()
            await fetchETA()
        }
        .onChange(of: locationManager.location) { _, _ in
            if shouldFetchDirections { Task { await fetchETA() } }
        }
        .onChange(of: mapItem) { _, _ in
            if shouldFetchDirections { Task { await fetchETA() } }
        }
        .onChange(of: userSettings.transportType) { _, _ in
            etaString = nil
            applyCachedDirections()
        }
        .onTapGesture {
            if allowsDetailPresentation {
                sheetPresented = true
            }
        }
        .sheet(isPresented: $sheetPresented) {
            IdeaView(
                card: card,
                mapItem: mapItem,
                etaString: etaString,
                transportType: userSettings.transportType,
                function: function ?? { _ in },
                allowsDeletion: allowsDeletion
            )
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    // MARK: - Event Card

    private var eventCard: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background { cardImage }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // Warm cream gradient from bottom
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 248/255, green: 246/255, blue: 240/255).opacity(0), location: 0),
                    .init(color: Color(red: 248/255, green: 246/255, blue: 240/255), location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                if let day = eventDayString {
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .environment(\.colorScheme, .light)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(venueTitle)
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.6)
                        .foregroundStyle(.black)

                    locationEtaRow(fontSize: 14, color: .black)

                    HStack(spacing: 8) {
                        if let locationType = card.ideas?.locationTypeLabel {
                            Text(locationType).fontWeight(.medium)
                        }
                        if let duration = card.ideas?.duration {
                            Text(duration)
                        }
                    }
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundStyle(.black.opacity(0.5))
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Location Card

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background { cardImage }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 8) {
                Text(venueTitle)
                    .font(.system(size: 20, weight: .medium))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)

                locationEtaRow(fontSize: 14, color: .secondary)

                HStack(spacing: 8) {
                    if let locationType = card.ideas?.locationTypeLabel {
                        Text(locationType).fontWeight(.medium)
                    }
                    if let duration = card.ideas?.duration {
                        Text(duration)
                    }
                }
                .font(.system(size: 14))
                .tracking(-0.35)
                .foregroundStyle(.primary.opacity(0.5))
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared

    @ViewBuilder
    private var cardImage: some View {
        if let mediaUrl = card.ideas?.media_url, let url = URL(string: mediaUrl) {
            let transaction = Transaction(
                animation: animatesImageLoading
                    ? .easeOut(duration: 0.2)
                    : nil
            )

            AsyncImage(url: url, transaction: transaction) { phase in
                switch phase {
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                default:
                    Color.gray.opacity(0.15)
                }
            }
        } else if let image {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.gray.opacity(0.15)
        }
    }

    @ViewBuilder
    private func locationEtaRow(fontSize: CGFloat, color: some ShapeStyle) -> some View {
        HStack(spacing: 4) {
            Text(card.ideas?.locationTypeLabel ?? "saved place")
            if let eta = etaString {
                Text("•")
                Image(systemName: userSettings.transportType.icon)
                Text(eta)
            }
        }
        .font(.system(size: fontSize))
        .tracking(-0.35)
        .foregroundStyle(color)
        .lineLimit(1)
    }

    // MARK: - Directions

    private var ideaID: Int {
        card.ideas?.id ?? card.id
    }

    private var shouldFetchDirections: Bool {
        loadsMapData && isNearViewport
    }

    private var directionsTaskID: String {
        "\(shouldFetchDirections)-\(userSettings.transportType.rawValue)"
    }

    private func applyCachedDirections() {
        if mapItem == nil, let cached = directionsCache.mapItem(for: ideaID) {
            mapItem = cached
        }
        if etaString == nil, let cached = directionsCache.eta(for: ideaID, transport: userSettings.transportType) {
            etaString = cached
        }
    }

    private func updateViewportProximity(_ frame: CGRect) {
        guard loadsMapData, frame.width > 1, frame.height > 1 else {
            if isNearViewport { isNearViewport = false }
            return
        }
        let padX = (frame.width + 16) * CGFloat(directionsPreloadCount)
        let padY = (frame.height + 20) * CGFloat(directionsPreloadCount)
        let near = viewportBounds.insetBy(dx: -padX, dy: -padY).intersects(frame)
        if near != isNearViewport {
            isNearViewport = near
        }
    }

    private var viewportBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.keyWindow?.bounds ?? scene?.windows.first?.bounds ?? .zero
    }

    private func fetchMapData() async {
        if mapItem != nil { return }
        guard let placeID = card.ideas?.place_id,
              let identifier = MKMapItem.Identifier(rawValue: placeID)
        else { return }

        let request = MKMapItemRequest(mapItemIdentifier: identifier)
        let item = await withCheckedContinuation { continuation in
            request.getMapItem { mapItem, _ in
                continuation.resume(returning: mapItem)
            }
        }
        guard !Task.isCancelled, let item else { return }
        mapItem = item
        directionsCache.store(mapItem: item, for: ideaID)
    }

    private func fetchETA() async {
        guard etaString == nil else { return }
        guard let destination = mapItem, locationManager.location != nil else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = userSettings.transportType.mkTransportType
        do {
            try Task.checkCancellation()
            let response = try await MKDirections(request: request).calculate()
            try Task.checkCancellation()
            guard let route = response.routes.first else { return }
            let interval = route.expectedTravelTime
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            etaString = h > 0 ? "\(h)h \(m)m" : "\(m)m"
            if let etaString {
                directionsCache.store(eta: etaString, for: ideaID, transport: userSettings.transportType)
            }
        } catch is CancellationError {
            return
        } catch {
            etaString = nil
        }
    }
}

@Observable
private final class CardLocationManager: NSObject, CLLocationManagerDelegate {
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

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

#Preview {
    ContentView()
}
