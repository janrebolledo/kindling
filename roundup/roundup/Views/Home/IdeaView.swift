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
    let address = "Eucalyptus, Trail Loop, Chino Hills, CA 91709, USA"

    @State private var mapItem: MKMapItem?

    var body: some View {

        ScrollView {

            ZStack(alignment: .bottom) {
                VStack {
                    GeometryReader { geometry in
                        Image("sample")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: geometry.size.width,
                                height: HERO_HEIGHT
                            )
                            .clipped()
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

                            Text("Eucalyptus Loop Trail")
                                .font(.editorialNew(.regular, size: 32))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 12) {
                                Text("⛰️ Outdoors")
                                Text("•")
                                Text("⛰️ Outdoors")
                                Text("•")
                                Text("⛰️ Outdoors")
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

            VStack {
                HStack {
                    Text("Chino Hills, California")
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
                                "Eucalyptus Loop Trail",
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
                }

            }
        }
        .ignoresSafeArea()
        .onAppear {
            Task {
                print("hi")
                if let request = MKGeocodingRequest(
                    addressString: address
                ) {
                    do {
                        let mapitems = try await request.mapItems
                        if let mapitem = mapitems.first {
                            mapItem = mapitem
                        }
                    } catch let error {
                        print("error: \(error)")
                    }
                }
            }
        }

    }

}

#Preview {
    IdeaView()
}
