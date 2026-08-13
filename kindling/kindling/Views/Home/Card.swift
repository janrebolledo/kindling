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
    @Environment(UserSettings.self) private var userSettings

    var function: ((ItemWrapper?) async -> Void)?
    var card: CardData
    var loadsMapData = true
    var allowsDetailPresentation = true
    var allowsDeletion = true
    var animatesImageLoading = false

    private var address: String {
        (card.ideas?.address ?? card.ideas?.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var venueTitle: String {
        card.ideas?.venue ?? "Untitled"
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
        .onAppear {
            if loadsMapData {
                locationManager.requestLocation()
            }
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
                if loadsMapData {
                    await fetchMapData()
                }
            }
        }
        .onChange(of: locationManager.location) { _, _ in
            if loadsMapData { Task { await fetchETA() } }
        }
        .onChange(of: mapItem) { _, _ in
            if loadsMapData { Task { await fetchETA() } }
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

                    if let hours = card.ideas?.open_hours,
                       let status = resolveOpenStatus(from: hours) {
                        HStack(spacing: 8) {
                            Text(status.isOpen ? "Open" : "Closed").fontWeight(.medium)
                            Text(status.detail)
                        }
                        .font(.system(size: 14))
                        .tracking(-0.35)
                        .foregroundStyle(.black.opacity(0.5))
                    } else {
                        HStack(spacing: 8) {
                            if let locationType = card.ideas?.location_type {
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

                if let hours = card.ideas?.open_hours,
                   let status = resolveOpenStatus(from: hours) {
                    HStack(spacing: 8) {
                        Text(status.isOpen ? "Open" : "Closed").fontWeight(.medium)
                        Text(status.detail)
                    }
                    .font(.system(size: 14))
                    .tracking(-0.35)
                    .foregroundStyle(.primary.opacity(0.5))
                } else {
                    HStack(spacing: 8) {
                        if let locationType = card.ideas?.location_type {
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
                        .transition(.blurFade)
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
            Text(card.ideas?.location ?? "—")
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

    // MARK: - Fetch

    private func fetchMapData() async {
        guard !address.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return }
            await MainActor.run { mapItem = item }
        } catch {
            print("MapKit search error: \(error)")
        }
    }

    private func fetchETA() async {
        guard let destination = mapItem, locationManager.location != nil else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = userSettings.transportType.mkTransportType
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return }
            let interval = route.expectedTravelTime
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            await MainActor.run { etaString = h > 0 ? "\(h)h \(m)m" : "\(m)m" }
        } catch {
            await MainActor.run { etaString = nil }
        }
    }
}

private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: 8, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
    }
}

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

