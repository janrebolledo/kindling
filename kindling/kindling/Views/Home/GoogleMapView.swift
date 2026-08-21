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
        mapView.settings.compassButton = true
        mapView.settings.myLocationButton = false
        mapView.isMyLocationEnabled = true
        mapView.mapType = .normal
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.onSelect = onSelect
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
