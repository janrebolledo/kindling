//
//  IdeaView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/19/26.
//

import MapKit
import SwiftUI

struct IdeaView: View {
    let HERO_HEIGHT: CGFloat = 500
    var card: CardData

    @State private var mapItem: MKMapItem?
    @State private var localImage: UIImage?

    private var address: String {
        (card.ideas?.location ?? card.ideas?.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
                            if let mediaUrl = card.ideas?.media_url, let url = URL(string: mediaUrl) {
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
                                    height: HERO_HEIGHT
                                )
                                .clipped()
                            } else if localImage != nil {
                                Image(uiImage: localImage!)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(
                                        width: geometry.size.width,
                                        height: HERO_HEIGHT
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
                        Text("from @fff")
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
                    }
                    .padding(32)
                    .frame(height: HERO_HEIGHT * 0.6)
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
                                if card.ideas?.location_type != nil {
                                    Text((card.ideas?.location_type!)!)
                                }
                                if card.ideas?.duration != nil {
                                    if card.ideas?.location_type != nil { Text("•") }
                                    Text((card.ideas?.duration!)!)
                                }
                                if card.ideas?.pricing != nil {
                                    if card.ideas?.location_type != nil || card.ideas?.duration != nil { Text("•") }
                                    HStack(spacing: 0) {
                                        ForEach(0..<(card.ideas?.pricing!)!, id: \.self) { _ in Text("$") }
                                        ForEach(0..<(3 - (card.ideas?.pricing!)!), id: \.self) { _ in
                                            Text("$").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .font(.neueMontreal(.regular, size: 16))
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: HERO_HEIGHT * 0.4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 20)

            VStack(spacing: 24) {
                HStack {
                    Text(address.isEmpty ? "—" : address)
                    Spacer()
                    Image(systemName: "car.fill")
                    Text("1h 8m")
                }
                .font(.neueMontreal(.regular, size: 16))
                .padding(.horizontal, 24)
                .foregroundStyle(.secondary)

                if mapItem != nil && mapItem?.location.coordinate != nil {
                    ZStack {

                        Map {

                            Marker(
                                venueTitle,
                                coordinate: (mapItem?.location.coordinate)!
                            )
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
//                        Text("loading map")
//                            .font(.neueMontreal(.regular, size: 16))
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding()
                }

                HStack {

                    Group {
                         if localImage != nil {
                            Image(uiImage: localImage!)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.gray.opacity(0.3))
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

                }

                Button("delete from collection & keep on device") {

                }
                .foregroundStyle(.secondary)
                .font(.neueMontreal(.regular, size: 14))
                .padding(.bottom, 72)

            }
        }
        .ignoresSafeArea()
        .onAppear {
            Task {
                localImage = try await loadImage(from: card.local_id)
                if !address.isEmpty, let request = MKGeocodingRequest(addressString: address) {
                    do {
                        let mapitems = try await request.mapItems
                        if let mapitem = mapitems.first {
                            mapItem = mapitem
                        }
                    } catch {
                        print("error: \(error)")
                    }
                }
            }
        }

    }

    private func placeholderImage(geometry: GeometryProxy) -> some View {
        VStack {Color.gray.opacity(0.2)}
            .frame(
                width: geometry.size.width,
                height: HERO_HEIGHT
            )
            .clipped()
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
        guard let d = date else { return "Screenshot on \(created)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "Screenshot on \(formatter.string(from: d))"
    }
}

#Preview {
    IdeaView(
        card: ItemWrapper(
            id: 0,
            local_id: "preview",
            ideas: Item(
                id: 0,
                name: nil,
                type: nil,
                description: nil,
                media_url: nil,
                address: "Eucalyptus, Trail Loop, Chino Hills, CA 91709, USA",
                location: nil,
                location_type: "Outdoors",
                duration: "2–3 hrs",
                pricing: 1,
                date: nil,
                time: nil,
                venue: "Eucalyptus Loop Trail",
                created_at: "2026-01-10"
            )
        )
    )
}
