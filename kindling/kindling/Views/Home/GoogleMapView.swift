import CoreLocation
import GoogleMaps
import SwiftUI
import UIKit

struct GoogleMapMarkerData: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let title: String
    let emoji: String
}

struct GoogleMapView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let markers: [GoogleMapMarkerData]
    let center: CLLocationCoordinate2D?
    let zoom: Float
    let selectedID: Int?
    let onSelect: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(
            latitude: center?.latitude ?? 37.7749,
            longitude: center?.longitude ?? -122.4194,
            zoom: zoom
        )
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        mapView.mapStyle = GMSMapStyle(jsonString: AppleMapsMapStyle.json(for: colorScheme))
        // Apple Maps keeps orientation chrome out of the way until it is useful.
        // The map remains rotatable; we just avoid a permanently visible compass.
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.isMyLocationEnabled = true
        mapView.mapType = .normal
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        mapView.mapStyle = GMSMapStyle(jsonString: AppleMapsMapStyle.json(for: colorScheme))
        mapView.clear()

        for markerData in markers {
            let marker = GMSMarker(position: markerData.coordinate)
            marker.title = markerData.title
            marker.userData = markerData.id
            marker.iconView = MarkerEmojiView(
                emoji: markerData.emoji,
                isSelected: selectedID == markerData.id
            )
            marker.groundAnchor = CGPoint(x: 0.5, y: 1)
            marker.map = mapView
        }

        if let center {
            let current = mapView.camera.target
            let moved = abs(current.latitude - center.latitude) > 0.0001
                || abs(current.longitude - center.longitude) > 0.0001
            if moved || mapView.camera.zoom != zoom {
                mapView.animate(to: GMSCameraPosition(
                    latitude: center.latitude,
                    longitude: center.longitude,
                    zoom: zoom
                ))
            }
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onSelect: (Int) -> Void

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? Int {
                onSelect(id)
            }
            return true
        }
    }
}

private enum AppleMapsMapStyle {
    static func json(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? dark : light
    }

    // A restrained palette inspired by Apple Maps: warm neutral land, cool
    // water, quiet labels, and clear white roads. This only changes Google's
    // presentation layer; map data, gestures, attribution, and place search
    // remain Google's.
    private static let light = """
    [
      {"featureType":"all","elementType":"geometry","stylers":[{"color":"#f3f2ee"}]},
      {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#687078"}]},
      {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#f3f2ee"},{"weight":2}]},
      {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#d7d9d6"},{"weight":1}]},
      {"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#e2e2de"}]},
      {"featureType":"landscape.natural","elementType":"geometry.fill","stylers":[{"color":"#e5efe1"}]},
      {"featureType":"landscape.natural.landcover","elementType":"geometry.fill","stylers":[{"color":"#e5efe1"}]},
      {"featureType":"poi","elementType":"geometry.fill","stylers":[{"color":"#e1eddd"}]},
      {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#d8ead7"}]},
      {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#dedfdb"},{"weight":0.7}]},
      {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#f6d98e"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#e4c477"},{"weight":1}]},
      {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
      {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#fbfbf9"}]},
      {"featureType":"transit","elementType":"geometry.fill","stylers":[{"color":"#e8dfe0"}]},
      {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#d5e8f4"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#718995"}]}
    ]
    """

    private static let dark = """
    [
      {"featureType":"all","elementType":"geometry","stylers":[{"color":"#202426"}]},
      {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#c3c9cc"}]},
      {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#202426"},{"weight":2}]},
      {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#3b4144"},{"weight":1}]},
      {"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#303639"}]},
      {"featureType":"landscape.natural","elementType":"geometry.fill","stylers":[{"color":"#27312d"}]},
      {"featureType":"landscape.natural.landcover","elementType":"geometry.fill","stylers":[{"color":"#27312d"}]},
      {"featureType":"poi","elementType":"geometry.fill","stylers":[{"color":"#29342f"}]},
      {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#263a30"}]},
      {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#343a3d"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#454b4e"},{"weight":0.7}]},
      {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#5b5947"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#736e50"},{"weight":1}]},
      {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#3b4144"}]},
      {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#303638"}]},
      {"featureType":"transit","elementType":"geometry.fill","stylers":[{"color":"#4a3d40"}]},
      {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#182c37"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#9db5c0"}]}
    ]
    """
}

extension GoogleMapView {
    init(
        coordinate: CLLocationCoordinate2D,
        title: String,
        isInteractive: Bool = true
    ) {
        self.init(
            markers: [
                GoogleMapMarkerData(
                    id: 0,
                    coordinate: coordinate,
                    title: title,
                    emoji: ""
                )
            ],
            center: coordinate,
            zoom: 15,
            selectedID: nil,
            onSelect: { _ in }
        )
    }
}

private final class MarkerEmojiView: UIView {
    init(emoji: String, isSelected: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: isSelected ? 50 : 42, height: isSelected ? 50 : 42))
        backgroundColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.88)
        layer.cornerRadius = bounds.width / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = isSelected ? 3 : 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        let label = UILabel(frame: bounds)
        label.text = emoji
        label.font = .systemFont(ofSize: isSelected ? 24 : 19)
        label.textAlignment = .center
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
