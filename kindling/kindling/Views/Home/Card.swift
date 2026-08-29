//
//  Card.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/23/26.
//
import CoreLocation
import Photos
import os
import SwiftUI

private actor CardImageCache {
    static let shared = CardImageCache()

    private var images: [String: UIImage] = [:]
    private var requests: [String: Task<UIImage?, Never>] = [:]

    func image(
        for key: String,
        loader: @escaping @Sendable () async -> UIImage?
    ) async -> UIImage? {
        if let image = images[key] { return image }
        if let request = requests[key] { return await request.value }

        let request = Task<UIImage?, Never> {
            await loader()
        }
        requests[key] = request

        let image = await request.value
        requests[key] = nil
        if let image { images[key] = image }
        return image
    }
}

struct Card: View {
    @State var image: UIImage? = nil
    @State private var imageRequestToken = UUID()
    @State var sheetPresented: Bool = false
    @State private var placeDetails: GooglePlaceDetails?
    @State private var etaString: String?
    @State private var isFetchingETA = false
    @State private var googlePlaceHours: GooglePlaceHours?
    @State private var locationManager: CardLocationManager?
    @State private var isNearViewport = false
    @Environment(UserSettings.self) private var userSettings
    @Environment(DirectionsCache.self) private var directionsCache

    private let directionsPreloadCount = 2
    private let thumbnailSize = CGSize(width: 600, height: 600)

    var function: ((ItemWrapper?) async -> Void)?
    var card: CardData
    var mapName: String? = nil
    var tapAction: (() -> Void)? = nil
    var loadsMapData = true
    var loadsPlaceDetails = false
    var loadsRemoteMedia = true
    var handlesTap = true
    var allowsDetailPresentation = true
    var allowsDeletion = true
    var animatesImageLoading = false

    private var venueTitle: String {
        mapName ?? placeDetails?.name ?? card.ideas?.name ?? "Untitled"
    }

    private var imageLoadID: String {
        "\(card.id)-\(card.local_id)-\(card.ideas?.media_url ?? "remote")"
    }

    private var googleMapsMediaURL: URL? {
        guard loadsRemoteMedia else { return nil }
        let value = placeDetails?.photoUrl ?? card.ideas?.media_url
        return value.flatMap(URL.init(string:))
    }

    private var isEvent: Bool {
        card.ideas?.type?.lowercased() == "event"
    }

    private var eventCardPrimaryColor: Color {
        .white
    }

    private var eventCardSecondaryColor: Color {
        .white.opacity(0.78)
    }

    private var eventCardDateBackground: Color {
        .white.opacity(0.22)
    }

    private var eventCardDateStroke: Color {
        .white.opacity(0.38)
    }

    private var eventDayString: String? {
        guard let dateString = card.ideas?.date?.trimmingCharacters(in: .whitespacesAndNewlines),
              !dateString.isEmpty else { return nil }

        let dateFormats = ["yyyy-MM-dd", "MM/dd/yyyy", "MMMM d, yyyy", "MMM d, yyyy"]
        let timeFormats = ["h:mm a", "h a", "HH:mm"]
        let locale = Locale(identifier: "en_US_POSIX")
        var parsedDate: Date?
        var hasTime = false

        if let timeString = card.ideas?.time?.trimmingCharacters(in: .whitespacesAndNewlines),
           !timeString.isEmpty {
            for dateFormat in dateFormats {
                for timeFormat in timeFormats {
                    let parser = DateFormatter()
                    parser.locale = locale
                    parser.calendar = Calendar.current
                    parser.dateFormat = "\(dateFormat) \(timeFormat)"
                    if let date = parser.date(from: "\(dateString) \(timeString)") {
                        parsedDate = date
                        hasTime = true
                        break
                    }
                }
                if parsedDate != nil { break }
            }
        }

        if parsedDate == nil {
            for dateFormat in dateFormats {
                let parser = DateFormatter()
                parser.locale = locale
                parser.calendar = Calendar.current
                parser.dateFormat = dateFormat
                if let date = parser.date(from: dateString) {
                    parsedDate = date
                    break
                }
            }
        }

        guard let parsedDate else { return dateString }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let eventDay = calendar.startOfDay(for: parsedDate)
        let isPast = eventDay < today || (eventDay == today && hasTime && parsedDate < now)

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = isPast ? "M/dd" : "EEEE"
        return formatter.string(from: parsedDate)
    }

    var body: some View {
        Group {
            if isEvent { eventCard } else { locationCard }
        }
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .if(loadsMapData) {
            $0.onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                updateViewportProximity(frame)
            }
        }
        .onAppear {
            if loadsMapData {
                applyCachedDirections()
            }
        }
        .task(id: imageLoadID) {
            let signpostID = KindlingProfiling.begin(KindlingProfiling.cardImageLoad)
            defer {
                KindlingProfiling.end(KindlingProfiling.cardImageLoad, id: signpostID)
            }

            let requestToken = UUID()
            imageRequestToken = requestToken
            image = nil
            guard !card.local_id.isEmpty else { return }

            let localID = card.local_id
            let targetSize = thumbnailSize
            let loadedImage = await CardImageCache.shared.image(for: localID) {
                try? await loadImage(
                    from: localID,
                    targetSize: targetSize,
                    resizeMode: .fast
                )
            }
            guard !Task.isCancelled, imageRequestToken == requestToken else { return }

            if animatesImageLoading {
                withAnimation(.easeOut(duration: 0.2)) {
                    image = loadedImage
                }
            } else {
                image = loadedImage
            }
        }
        .task(id: mapDataTaskID) {
            guard shouldLoadPlaceData else { return }
            applyCachedDirections()
            await fetchPlaceDetails()

            guard shouldFetchDirections else { return }
            if placeDetails != nil, etaString != nil { return }
            requestLocationIfNeeded()
            await fetchETA()
        }
        .onChange(of: locationManager?.location) { _, _ in
            if shouldFetchDirections { Task { await fetchETA() } }
        }
        .onChange(of: placeDetails?.id) { _, _ in
            if shouldFetchDirections { Task { await fetchETA() } }
        }
        .onChange(of: userSettings.transportType) { _, _ in
            etaString = nil
            applyCachedDirections()
        }
        .if(handlesTap) {
            $0.onTapGesture {
                if let tapAction {
                    tapAction()
                } else if allowsDetailPresentation {
                    sheetPresented = true
                }
            }
        }
        .sheet(isPresented: $sheetPresented) {
            IdeaView(
                card: card,
                placeDetails: placeDetails,
                etaString: etaString,
                googlePlaceHours: googlePlaceHours,
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

            eventCardGradient
                .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                if let day = eventDayString {
                    Text(day)
                        .font(.system(size: 14, weight: .medium))
                        .tracking(-0.35)
                        .foregroundStyle(eventCardPrimaryColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(eventCardDateBackground, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(eventCardDateStroke, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(venueTitle)
                        .font(.system(size: 24, weight: .medium))
                        .tracking(-0.6)
                        .foregroundStyle(eventCardPrimaryColor)

                    locationEtaRow(fontSize: 14, color: eventCardPrimaryColor)

                    googlePlaceStatusOrFallbackRow(
                        fontSize: 14,
                        color: eventCardSecondaryColor
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var eventCardGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.02),
                .init(color: Color.black.opacity(0.08), location: 0.24),
                .init(color: Color.black.opacity(0.42), location: 0.50),
                .init(color: Color.black.opacity(0.80), location: 0.74),
                .init(color: Color.black.opacity(0.96), location: 0.92),
                .init(color: .black, location: 1),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
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

                googlePlaceStatusOrFallbackRow(
                    fontSize: 14,
                    color: .secondary
                )
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared

    @ViewBuilder
    private var cardImage: some View {
        if let url = googleMapsMediaURL {
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
                case .empty:
                    // Keep the Google photo first-class while it loads. The
                    // screenshot is only a fallback after the request fails.
                    Color.gray.opacity(0.15)
                case .failure:
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.15)
                    }
                @unknown default:
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.gray.opacity(0.15)
                    }
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

    private var shouldLoadPlaceData: Bool {
        card.ideas?.place_id != nil
            && (loadsPlaceDetails || (loadsMapData && isNearViewport))
    }

    private var mapDataTaskID: String {
        "\(shouldLoadPlaceData)-\(shouldFetchDirections)-\(userSettings.transportType.rawValue)"
    }

    private func applyCachedDirections() {
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

    private func fetchPlaceDetails() async {
        guard placeDetails == nil, let placeID = card.ideas?.place_id else { return }
        let signpostID = KindlingProfiling.begin(KindlingProfiling.cardPlaceDetails)
        defer {
            KindlingProfiling.end(KindlingProfiling.cardPlaceDetails, id: signpostID)
        }

        let details = await GooglePlacesService.shared.details(for: placeID)
        guard !Task.isCancelled else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            placeDetails = details
            googlePlaceHours = details?.hours
        }
    }

    private func requestLocationIfNeeded() {
        guard loadsMapData else { return }
        if locationManager == nil {
            locationManager = CardLocationManager()
        }
        locationManager?.requestLocation()
    }

    @ViewBuilder
    private func googlePlaceStatusRow(fontSize: CGFloat, color: some ShapeStyle) -> some View {
        if let status = googlePlaceHours?.status {
            if !status.isOpen && status.detail.hasPrefix("Opens") {
                HStack(spacing: 8) {
                    Text(status.detail)
                    if let priceLevel = placeDetails?.priceLevelLabel {
                        Text(priceLevel)
                    }
                }
                    .font(.system(size: fontSize))
                    .tracking(-0.35)
                    .foregroundStyle(color)
                    .lineLimit(1)
            } else {
                HStack(spacing: 8) {
                    Text(status.isOpen ? "Open" : "Closed").fontWeight(.medium)
                    Text(status.detail)
                    if let priceLevel = placeDetails?.priceLevelLabel {
                        Text(priceLevel)
                    }
                }
                .font(.system(size: fontSize))
                .tracking(-0.35)
                .foregroundStyle(color)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func googlePlaceStatusOrFallbackRow(
        fontSize: CGFloat,
        color: some ShapeStyle
    ) -> some View {
        if let activityDetails = card.ideas?.activityDetailsLabel {
            HStack(spacing: 8) {
                if let locationType = card.ideas?.locationTypeLabel {
                    Text(locationType).fontWeight(.medium)
                }
                Text(activityDetails)
                if let priceLevel = placeDetails?.priceLevelLabel {
                    Text(priceLevel)
                }
            }
            .font(.system(size: fontSize))
            .tracking(-0.35)
            .foregroundStyle(color)
        } else if googlePlaceHours?.status != nil {
            googlePlaceStatusRow(fontSize: fontSize, color: color)
        } else {
            HStack(spacing: 8) {
                if let locationType = card.ideas?.locationTypeLabel {
                    Text(locationType).fontWeight(.medium)
                }
                if let activityDetails = card.ideas?.activityDetailsLabel {
                    Text(activityDetails)
                } else if let duration = card.ideas?.duration {
                    Text(duration)
                }
                if let priceLevel = placeDetails?.priceLevelLabel {
                    Text(priceLevel)
                }
            }
            .font(.system(size: fontSize))
            .tracking(-0.35)
            .foregroundStyle(color)
        }
    }

    private func fetchETA() async {
        guard etaString == nil, !isFetchingETA,
              let destination = placeDetails?.coordinate else { return }

        isFetchingETA = true
        defer { isFetchingETA = false }

        do {
            try Task.checkCancellation()
            requestLocationIfNeeded()

            // Authorization can finish after requestLocation() returns. Wait
            // briefly for the delegate callback before giving up; the
            // location change observer will retry when a later fix arrives.
            for _ in 0..<30 {
                if let origin = locationManager?.location?.coordinate {
                    etaString = await GooglePlacesService.shared.route(
                        from: origin,
                        to: destination,
                        transportType: userSettings.transportType
                    )
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                try Task.checkCancellation()
            }

            try Task.checkCancellation()
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
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else { return }
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
