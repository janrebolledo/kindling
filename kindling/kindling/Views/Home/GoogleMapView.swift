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
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.mapStyle = try? GMSMapStyle(jsonString: KindlingMapStyle.json(for: colorScheme))
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
        context.coordinator.hitTargets = markers.map {
            MarkerHitTarget(id: $0.id, coordinate: $0.coordinate)
        }
        mapView.mapStyle = try? GMSMapStyle(jsonString: KindlingMapStyle.json(for: colorScheme))
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
            marker.zIndex = selectedID == markerData.id ? 1 : 0
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
        fileprivate var hitTargets: [MarkerHitTarget] = []

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let id = marker.userData as? Int {
                onSelect(id)
            }
            return true
        }

        // Custom iconViews can have a smaller effective hit area than their
        // rendered bounds. Treat a nearby map tap as a pin tap as well so the
        // emoji does not need pixel-perfect targeting.
        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            let tapPoint = mapView.projection.point(for: coordinate)
            var nearestID: Int?
            var nearestDistance = CGFloat.greatestFiniteMagnitude

            for target in hitTargets {
                let markerPoint = mapView.projection.point(for: target.coordinate)
                let dx = markerPoint.x - tapPoint.x
                let dy = markerPoint.y - tapPoint.y
                let distance = sqrt(dx * dx + dy * dy)
                guard distance <= 34, distance < nearestDistance else { continue }
                nearestID = target.id
                nearestDistance = distance
            }

            if let nearestID {
                onSelect(nearestID)
            }
        }
    }
}

fileprivate struct MarkerHitTarget {
    let id: Int
    let coordinate: CLLocationCoordinate2D
}

private enum KindlingMapStyle {
    static func json(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? dark : light
    }

    // Use Kindling's warm ivory, peach, orange, and charcoal palette while
    // keeping enough contrast between land, water, roads, and labels. This
    // only changes Google's presentation layer; map data, gestures,
    // attribution, and place search remain Google's.
    private static let light = """
    [
      {"featureType":"all","elementType":"geometry","stylers":[{"color":"#fbf7f1"}]},
      {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#6b625a"}]},
      {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#fbf7f1"},{"weight":2}]},
      {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#e5d9cc"},{"weight":1}]},
      {"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#eee3d7"}]},
      {"featureType":"landscape.natural","elementType":"geometry.fill","stylers":[{"color":"#f4ead9"}]},
      {"featureType":"landscape.natural.landcover","elementType":"geometry.fill","stylers":[{"color":"#f2e6d3"}]},
      {"featureType":"poi","elementType":"geometry.fill","stylers":[{"color":"#f7e3c9"}]},
      {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#f1d8b9"}]},
      {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#fffdf9"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#e5d9cc"},{"weight":0.7}]},
      {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#ffc77a"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#ee9b43"},{"weight":1}]},
      {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#fffaf4"}]},
      {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#fefcf8"}]},
      {"featureType":"transit","elementType":"geometry.fill","stylers":[{"color":"#f1d5c1"}]},
      {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#e6e8e2"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#7a756d"}]}
    ]
    """

    private static let dark = """
    [
      {"featureType":"all","elementType":"geometry","stylers":[{"color":"#241f1b"}]},
      {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#d7cec3"}]},
      {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#241f1b"},{"weight":2}]},
      {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#4a4038"},{"weight":1}]},
      {"featureType":"administrative.land_parcel","elementType":"geometry.stroke","stylers":[{"color":"#38302a"}]},
      {"featureType":"landscape.natural","elementType":"geometry.fill","stylers":[{"color":"#332a23"}]},
      {"featureType":"landscape.natural.landcover","elementType":"geometry.fill","stylers":[{"color":"#302720"}]},
      {"featureType":"poi","elementType":"geometry.fill","stylers":[{"color":"#3b2d22"}]},
      {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#3a3027"}]},
      {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#3a332e"}]},
      {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#50463e"},{"weight":0.7}]},
      {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#9b562d"}]},
      {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#bd7140"},{"weight":1}]},
      {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#403832"}]},
      {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#302a26"}]},
      {"featureType":"transit","elementType":"geometry.fill","stylers":[{"color":"#523b31"}]},
      {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
      {"featureType":"water","elementType":"geometry.fill","stylers":[{"color":"#2d3431"}]},
      {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#aaa59c"}]}
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
        // Keep the visible pin compact while giving Google Maps a forgiving
        // touch target around it.
        let hitSize: CGFloat = isSelected ? 58 : 54
        let visibleSize: CGFloat = isSelected ? 50 : 42
        super.init(frame: CGRect(x: 0, y: 0, width: hitSize, height: hitSize))
        backgroundColor = .clear

        let inset = (hitSize - visibleSize) / 2
        let bubble = UIView(frame: CGRect(x: inset, y: inset, width: visibleSize, height: visibleSize))
        bubble.backgroundColor = isSelected ? .white : UIColor.white.withAlphaComponent(0.88)
        bubble.layer.cornerRadius = visibleSize / 2
        bubble.layer.borderColor = UIColor.white.cgColor
        bubble.layer.borderWidth = isSelected ? 3 : 1
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.16
        bubble.layer.shadowRadius = 5
        bubble.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(bubble)

        let label = UILabel(frame: bubble.bounds)
        label.text = emoji
        label.font = .systemFont(ofSize: isSelected ? 24 : 19)
        label.textAlignment = .center
        bubble.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
