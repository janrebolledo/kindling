import CoreLocation
import GoogleMaps
import SwiftUI
import UIKit

struct GoogleMapMarkerData: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let title: String
    let emoji: String
    let clusterMemberIDs: [Int]?

    var isCluster: Bool { clusterMemberIDs != nil }

    init(
        id: Int,
        coordinate: CLLocationCoordinate2D,
        title: String,
        emoji: String,
        clusterMemberIDs: [Int]? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.emoji = emoji
        self.clusterMemberIDs = clusterMemberIDs
    }
}

struct GoogleMapView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let markers: [GoogleMapMarkerData]
    let center: CLLocationCoordinate2D?
    let zoom: Float
    let centerRequestID: Int
    let isInteractive: Bool
    let selectedID: Int?
    let onSelect: (Int) -> Void
    let onDeselect: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onDeselect: onDeselect)
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
        context.coordinator.lastCenterRequestID = centerRequestID
        context.coordinator.appliedIsDark = colorScheme == .dark
        context.coordinator.reduceMotion = reduceMotion
        mapView.mapStyle = try? GMSMapStyle(jsonString: KindlingMapStyle.json(for: colorScheme))
        mapView.isUserInteractionEnabled = isInteractive
        mapView.settings.scrollGestures = isInteractive
        mapView.settings.zoomGestures = isInteractive
        mapView.settings.rotateGestures = isInteractive
        mapView.settings.tiltGestures = isInteractive
        // Apple Maps keeps orientation chrome out of the way until it is useful.
        // The map remains rotatable; we just avoid a permanently visible compass.
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.isMyLocationEnabled = isInteractive
        // This screen only needs the base map and saved-place overlays. Keep
        // optional 3D/traffic layers out of the renderer's work.
        mapView.isBuildingsEnabled = false
        mapView.isIndoorEnabled = false
        mapView.isTrafficEnabled = false
        mapView.mapType = .normal
        context.coordinator.lastIsInteractive = isInteractive
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let signpostID = KindlingProfiling.begin(KindlingProfiling.mapUpdateUIView)
        defer {
            KindlingProfiling.end(KindlingProfiling.mapUpdateUIView, id: signpostID)
        }

        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onDeselect = onDeselect
        coordinator.reduceMotion = reduceMotion

        let rawMarkerInputSignatures = markers.map {
            MarkerInputSignature(
                id: $0.id,
                coordinate: $0.coordinate,
                title: $0.title,
                emoji: $0.emoji,
                isSelected: selectedID == $0.id,
                clusterMemberIDs: $0.clusterMemberIDs
            )
        }
        let markerInputsChanged = coordinator.lastRawMarkerInputSignatures != rawMarkerInputSignatures
        let zoomBucket = Coordinator.zoomBucket(for: mapView.camera.zoom)
        let zoomBucketChanged = coordinator.lastDisplayedZoomBucket != zoomBucket

        // SwiftUI can call updateUIView for unrelated state changes, such as
        // an image finishing its load in a sibling view. Re-parsing the style
        // and rebuilding every overlay on each call causes visible map work
        // during scrolling and navigation transitions.
        let isDark = colorScheme == .dark
        let colorSchemeChanged = coordinator.appliedIsDark != isDark
        let interactionFlagsChanged = coordinator.lastIsInteractive != isInteractive
        let hasPendingCameraRequest = coordinator.lastCenterRequestID != centerRequestID
            && center != nil

        guard markerInputsChanged
            || zoomBucketChanged
            || colorSchemeChanged
            || interactionFlagsChanged
            || hasPendingCameraRequest else {
            return
        }

        if markerInputsChanged || zoomBucketChanged {
            coordinator.rawMarkerData = markers
            coordinator.rawSelectedID = selectedID
            coordinator.lastRawMarkerInputSignatures = rawMarkerInputSignatures
            coordinator.updateMarkerDisplay(on: mapView, zoom: mapView.camera.zoom)
        }

        if colorSchemeChanged {
            mapView.mapStyle = try? GMSMapStyle(jsonString: KindlingMapStyle.json(for: colorScheme))
            coordinator.appliedIsDark = isDark
        }

        if interactionFlagsChanged {
            mapView.isUserInteractionEnabled = isInteractive
            mapView.settings.scrollGestures = isInteractive
            mapView.settings.zoomGestures = isInteractive
            mapView.settings.rotateGestures = isInteractive
            mapView.settings.tiltGestures = isInteractive
            mapView.isMyLocationEnabled = isInteractive
            coordinator.lastIsInteractive = isInteractive
        }

        if let center {
            let requestedAgain = coordinator.lastCenterRequestID != centerRequestID
            // `updateUIView` can run several times while a camera animation is
            // in flight (for example when selecting a pin also presents the
            // detail sheet). Re-triggering from the camera's intermediate
            // position restarts the animation and makes it look stuttery.
            // Camera changes are explicitly versioned by the request ID, so
            // animate only when a new request arrives.
            if requestedAgain {
                mapView.animate(to: GMSCameraPosition(
                    latitude: center.latitude,
                    longitude: center.longitude,
                    zoom: zoom
                ))
            }
            coordinator.lastCenterRequestID = centerRequestID
        }
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onSelect: (Int) -> Void
        var onDeselect: () -> Void
        fileprivate var hitTargets: [MarkerHitTarget] = []
        fileprivate var lastHitTargetSignatures: [MarkerHitTargetSignature]?
        fileprivate var lastMarkerInputSignatures: [MarkerInputSignature]?
        fileprivate var lastRawMarkerInputSignatures: [MarkerInputSignature]?
        fileprivate var lastDisplayedZoomBucket: Int?
        fileprivate var lastCenterRequestID: Int?
        fileprivate var appliedIsDark: Bool?
        fileprivate var lastIsInteractive: Bool?
        fileprivate var rawMarkerData: [GoogleMapMarkerData] = []
        fileprivate var rawSelectedID: Int?
        fileprivate var reduceMotion = false
        private var markersByID: [Int: GMSMarker] = [:]
        private var markerSignatures: [Int: MarkerInputSignature] = [:]
        private var lastViewportCameraTarget: CLLocationCoordinate2D?
        private var lastViewportZoom: Float?

        init(onSelect: @escaping (Int) -> Void, onDeselect: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onDeselect = onDeselect
        }

        static func zoomBucket(for zoom: Float) -> Int {
            Int((zoom * 2).rounded())
        }

        func updateMarkerDisplay(on mapView: GMSMapView, zoom: Float) {
            let displayMarkers = clusteredMarkers(rawMarkerData, zoom: zoom, on: mapView)
            let hitTargetSignatures = displayMarkers.map {
                MarkerHitTargetSignature(
                    id: $0.id,
                    coordinate: $0.coordinate,
                    isSelected: rawSelectedID == $0.id,
                    clusterMemberIDs: $0.clusterMemberIDs
                )
            }

            if lastHitTargetSignatures != hitTargetSignatures {
                hitTargets = hitTargetSignatures.map { MarkerHitTarget($0) }
                lastHitTargetSignatures = hitTargetSignatures
            }

            updateMarkers(displayMarkers, selectedID: rawSelectedID, on: mapView)
            lastViewportCameraTarget = mapView.camera.target
            lastViewportZoom = zoom
            lastDisplayedZoomBucket = Self.zoomBucket(for: zoom)
        }

        private func clusteredMarkers(
            _ markers: [GoogleMapMarkerData],
            zoom: Float,
            on mapView: GMSMapView
        ) -> [GoogleMapMarkerData] {
            // GMSMarker overlays remain active even when Google Maps has
            // panned them off-screen. Cull against the projected viewport
            // before clustering so both the overlay count and the clustering
            // work stay proportional to what the user can see.
            let viewportMarkers = markersInViewport(markers, on: mapView)

            guard viewportMarkers.count > MapClusteringMetrics.minimumMarkersToCluster,
                  zoom < MapClusteringMetrics.stopClusteringAtZoom else {
                return viewportMarkers
            }

            let cellSize = MapClusteringMetrics.cellPoints
                / (256 * pow(2, CGFloat(zoom)))
            var buckets: [ClusterGridKey: [GoogleMapMarkerData]] = [:]

            for marker in viewportMarkers {
                let worldPoint = Self.worldPoint(for: marker.coordinate)
                let key = ClusterGridKey(
                    x: Int(floor(worldPoint.x / cellSize)),
                    y: Int(floor(worldPoint.y / cellSize))
                )
                buckets[key, default: []].append(marker)
            }

            return buckets.keys.sorted().flatMap { key in
                let members = buckets[key, default: []]
                guard members.count > 1 else { return members }

                let latitude = members.map { $0.coordinate.latitude }.reduce(0, +)
                    / CLLocationDegrees(members.count)
                let longitude = members.map { $0.coordinate.longitude }.reduce(0, +)
                    / CLLocationDegrees(members.count)
                let memberIDs = members.map(\.id).sorted()
                let clusterID = -(key.x * 100_000 + key.y + 1)

                return [GoogleMapMarkerData(
                    id: clusterID,
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    title: "\(members.count) saved places",
                    emoji: "\(members.count)",
                    clusterMemberIDs: memberIDs
                )]
            }
        }

        private func markersInViewport(
            _ markers: [GoogleMapMarkerData],
            on mapView: GMSMapView
        ) -> [GoogleMapMarkerData] {
            let viewport = mapView.bounds.insetBy(
                dx: -MapViewportMetrics.prefetchPoints,
                dy: -MapViewportMetrics.prefetchPoints
            )

            // The first update can happen before the map has its final
            // layout. Keep the initial render reliable; the next SwiftUI
            // update and every camera idle will apply the culling pass.
            guard viewport.width > 0, viewport.height > 0 else { return markers }

            return markers.filter { marker in
                // Keep the selected marker alive during a camera animation.
                // It will be culled normally as soon as selection ends.
                guard marker.id != rawSelectedID else { return true }
                return viewport.contains(mapView.projection.point(for: marker.coordinate))
            }
        }

        private static func worldPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            let latitude = max(-85.05112878, min(85.05112878, coordinate.latitude))
            let sinLatitude = sin(latitude * .pi / 180)
            return CGPoint(
                x: (coordinate.longitude + 180) / 360,
                y: 0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * .pi)
            )
        }

        func updateMarkers(
            _ markerData: [GoogleMapMarkerData],
            selectedID: Int?,
            on mapView: GMSMapView
        ) {
            let signpostID = KindlingProfiling.begin(KindlingProfiling.mapUpdateMarkers)
            defer {
                KindlingProfiling.end(KindlingProfiling.mapUpdateMarkers, id: signpostID)
            }

            let markerInputSignatures = markerData.map {
                MarkerInputSignature(
                    id: $0.id,
                    coordinate: $0.coordinate,
                    title: $0.title,
                    emoji: $0.emoji,
                    isSelected: selectedID == $0.id,
                    clusterMemberIDs: $0.clusterMemberIDs
                )
            }
            guard lastMarkerInputSignatures != markerInputSignatures else {
                return
            }
            lastMarkerInputSignatures = markerInputSignatures

            let incomingIDs = Set(markerData.map(\.id))
            var newMarkers: [(marker: GMSMarker, data: GoogleMapMarkerData)] = []

            let staleIDs = markersByID.keys.filter { !incomingIDs.contains($0) }
            for id in staleIDs {
                markersByID[id]?.map = nil
                markersByID.removeValue(forKey: id)
                markerSignatures.removeValue(forKey: id)
            }

            for data in markerData {
                let signature = MarkerInputSignature(
                    id: data.id,
                    coordinate: data.coordinate,
                    title: data.title,
                    emoji: data.emoji,
                    isSelected: selectedID == data.id,
                    clusterMemberIDs: data.clusterMemberIDs
                )

                if let marker = markersByID[data.id] {
                    let oldSignature = markerSignatures[data.id]
                    if oldSignature?.coordinate != signature.coordinate {
                        marker.position = data.coordinate
                    }
                    if oldSignature?.title != signature.title {
                        marker.title = data.title
                    }
                    if oldSignature?.emoji != signature.emoji
                        || oldSignature?.clusterMemberIDs != signature.clusterMemberIDs
                        || oldSignature?.isSelected != signature.isSelected {
                        marker.iconView = nil
                        marker.tracksViewChanges = false
                        marker.icon = data.isCluster
                            ? MarkerIconRenderer.cluster
                            : MarkerIconRenderer.emoji(
                                data.emoji,
                                isSelected: signature.isSelected
                            )
                    }
                    if oldSignature?.isSelected != signature.isSelected {
                        marker.zIndex = signature.isSelected ? 1 : 0
                    }
                    if oldSignature?.clusterMemberIDs != signature.clusterMemberIDs {
                        marker.userData = MarkerPayload(
                            id: data.id,
                            clusterMemberIDs: data.clusterMemberIDs
                        )
                        marker.groundAnchor = CGPoint(
                            x: 0.5,
                            y: data.isCluster ? 0.5 : MarkerInteractionMetrics.groundAnchorY
                        )
                    }
                } else {
                    let marker = GMSMarker(position: data.coordinate)
                    marker.title = data.title
                    marker.userData = MarkerPayload(
                        id: data.id,
                        clusterMemberIDs: data.clusterMemberIDs
                    )
                    let icon = data.isCluster
                        ? MarkerIconRenderer.cluster
                        : MarkerIconRenderer.emoji(
                            data.emoji,
                            isSelected: signature.isSelected
                        )
                    let iconView = UIImageView(image: icon)
                    iconView.frame = CGRect(origin: .zero, size: icon.size)
                    iconView.isUserInteractionEnabled = false
                    iconView.alpha = MarkerAppearanceMetrics.startingOpacity
                    iconView.transform = reduceMotion
                        ? .identity
                        : CGAffineTransform(
                            scaleX: MarkerAppearanceMetrics.startingScale,
                            y: MarkerAppearanceMetrics.startingScale
                        )
                    marker.iconView = iconView
                    marker.tracksViewChanges = true
                    marker.groundAnchor = CGPoint(
                        x: 0.5,
                        y: data.isCluster ? 0.5 : MarkerInteractionMetrics.groundAnchorY
                    )
                    marker.zIndex = signature.isSelected ? 1 : 0
                    marker.map = mapView
                    markersByID[data.id] = marker
                    newMarkers.append((marker: marker, data: data))
                }

                markerSignatures[data.id] = signature
            }

            animateNewMarkers(newMarkers)
        }

        private func animateNewMarkers(
            _ entries: [(marker: GMSMarker, data: GoogleMapMarkerData)]
        ) {
            let sortedEntries = entries.sorted { $0.data.id < $1.data.id }

            for (index, entry) in sortedEntries.enumerated() {
                guard let iconView = entry.marker.iconView else { continue }

                let delay = reduceMotion
                    ? 0
                    : min(
                        TimeInterval(index) * MarkerAppearanceMetrics.stagger,
                        MarkerAppearanceMetrics.maximumStagger
                    )
                let timing = UICubicTimingParameters(
                    controlPoint1: CGPoint(x: 0.23, y: 1),
                    controlPoint2: CGPoint(x: 0.32, y: 1)
                )
                let animator = UIViewPropertyAnimator(
                    duration: reduceMotion
                        ? MarkerAppearanceMetrics.reducedMotionDuration
                        : MarkerAppearanceMetrics.duration,
                    timingParameters: timing
                )
                animator.addAnimations {
                    iconView.alpha = 1
                    iconView.transform = .identity
                }
                animator.addCompletion { _ in
                    entry.marker.tracksViewChanges = false
                }
                animator.startAnimation(afterDelay: delay)
            }
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            guard !rawMarkerData.isEmpty else { return }
            // The visible set changes when panning even if the zoom bucket
            // stays the same. Re-run the cheap viewport filter on every idle;
            // updateMarkers still returns immediately when the display set
            // did not change.
            updateMarkerDisplay(on: mapView, zoom: position.zoom)
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            guard !rawMarkerData.isEmpty,
                  shouldRefreshViewport(for: position, on: mapView) else {
                return
            }
            // Refresh in coarse steps during a gesture. This removes stale
            // off-screen overlays without doing marker churn on every camera
            // frame; idleAt performs the final exact pass.
            updateMarkerDisplay(on: mapView, zoom: position.zoom)
        }

        private func shouldRefreshViewport(
            for position: GMSCameraPosition,
            on mapView: GMSMapView
        ) -> Bool {
            guard let lastViewportCameraTarget,
                  let lastViewportZoom else {
                return true
            }

            guard abs(position.zoom - lastViewportZoom)
                    < MapViewportMetrics.zoomRefreshDelta else {
                return true
            }

            let previousPoint = mapView.projection.point(for: lastViewportCameraTarget)
            let currentPoint = mapView.projection.point(for: position.target)
            let dx = currentPoint.x - previousPoint.x
            let dy = currentPoint.y - previousPoint.y
            return hypot(dx, dy) >= MapViewportMetrics.cameraRefreshPoints
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let payload = marker.userData as? MarkerPayload {
                if let memberIDs = payload.clusterMemberIDs, !memberIDs.isEmpty {
                    zoomIntoCluster(at: marker.position, on: mapView)
                } else {
                    onSelect(payload.id)
                }
            } else if let id = marker.userData as? Int {
                // Preserve compatibility with any marker created before the
                // cluster payload was introduced.
                onSelect(id)
            }
            return true
        }

        // Custom marker icons can have a smaller effective hit area than their
        // rendered bounds. Treat a nearby map tap as a pin tap as well so the
        // emoji does not need pixel-perfect targeting.
        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            selectNearestMarker(at: coordinate, on: mapView)
        }

        private func selectNearestMarker(
            at coordinate: CLLocationCoordinate2D,
            on mapView: GMSMapView
        ) {
            let tapPoint = mapView.projection.point(for: coordinate)
            var nearestTarget: MarkerHitTarget?
            var nearestDistance = CGFloat.greatestFiniteMagnitude

            for target in hitTargets {
                let markerPoint = mapView.projection.point(for: target.coordinate)
                let hitCenter = CGPoint(
                    x: markerPoint.x,
                    y: markerPoint.y + target.hitCenterOffsetY
                )
                let dx = hitCenter.x - tapPoint.x
                let dy = hitCenter.y - tapPoint.y
                let distance = sqrt(dx * dx + dy * dy)
                guard distance <= MarkerInteractionMetrics.fallbackHitRadius,
                      distance < nearestDistance else { continue }
                nearestTarget = target
                nearestDistance = distance
            }

            if let nearestTarget {
                if let memberIDs = nearestTarget.clusterMemberIDs, !memberIDs.isEmpty {
                    zoomIntoCluster(at: nearestTarget.coordinate, on: mapView)
                } else {
                    onSelect(nearestTarget.id)
                }
            } else {
                onDeselect()
            }
        }

        private func zoomIntoCluster(
            at coordinate: CLLocationCoordinate2D,
            on mapView: GMSMapView
        ) {
            let nextZoom = min(mapView.camera.zoom + 2, 18)
            mapView.animate(to: GMSCameraPosition(target: coordinate, zoom: nextZoom))
        }

        func mapView(
            _ mapView: GMSMapView,
            didTapPOIWithPlaceID placeID: String,
            name: String,
            location: CLLocationCoordinate2D
        ) {
            // Google can route taps on map POIs here instead of didTapAt. Run
            // the same nearby-marker check so a POI label cannot steal a tap
            // from a pin sitting beside it.
            selectNearestMarker(at: location, on: mapView)
        }
    }
}

fileprivate struct MarkerHitTarget {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let hitCenterOffsetY: CGFloat
    let clusterMemberIDs: [Int]?

    init(_ signature: MarkerHitTargetSignature) {
        self.id = signature.id
        self.coordinate = signature.coordinate
        self.clusterMemberIDs = signature.clusterMemberIDs
        let hitSize = signature.isSelected
            ? MarkerInteractionMetrics.selectedHitSize
            : signature.clusterMemberIDs == nil
                ? MarkerInteractionMetrics.hitSize
                : MarkerInteractionMetrics.clusterHitSize
        let groundAnchorY = signature.clusterMemberIDs == nil
            ? MarkerInteractionMetrics.groundAnchorY
            : 0.5
        self.hitCenterOffsetY = (0.5 - groundAnchorY) * hitSize
    }

    init(id: Int, coordinate: CLLocationCoordinate2D, isSelected: Bool) {
        self.id = id
        self.coordinate = coordinate
        self.clusterMemberIDs = nil
        let hitSize = isSelected
            ? MarkerInteractionMetrics.selectedHitSize
            : MarkerInteractionMetrics.hitSize
        self.hitCenterOffsetY = (0.5 - MarkerInteractionMetrics.groundAnchorY) * hitSize
    }
}

fileprivate struct MarkerHitTargetSignature: Equatable {
    let id: Int
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let isSelected: Bool
    let clusterMemberIDs: [Int]?

    init(
        id: Int,
        coordinate: CLLocationCoordinate2D,
        isSelected: Bool,
        clusterMemberIDs: [Int]? = nil
    ) {
        self.id = id
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.isSelected = isSelected
        self.clusterMemberIDs = clusterMemberIDs
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private enum MarkerInteractionMetrics {
    static let hitSize: CGFloat = 72
    static let selectedHitSize: CGFloat = 72
    static let clusterHitSize: CGFloat = 64
    static let fallbackHitRadius: CGFloat = 38
    static let groundAnchorY: CGFloat = 0.875
}

private enum MarkerAppearanceMetrics {
    // Emil's guidance favors a restrained entrance over a pop from a tiny
    // scale. Keep the requested opacity change while starting at 90% size.
    static let startingScale: CGFloat = 0.9
    static let startingOpacity: CGFloat = 0.3
    static let duration: TimeInterval = 0.24
    static let reducedMotionDuration: TimeInterval = 0.18
    static let stagger: TimeInterval = 0.04
    static let maximumStagger: TimeInterval = 0.4
}

private enum MapClusteringMetrics {
    static let minimumMarkersToCluster = 24
    static let stopClusteringAtZoom: Float = 13
    static let cellPoints: CGFloat = 72
}

private enum MapViewportMetrics {
    // A small buffer keeps pins from popping in at the edge while still
    // dropping the vast majority of off-screen overlays.
    static let prefetchPoints: CGFloat = 96
    static let cameraRefreshPoints: CGFloat = 128
    static let zoomRefreshDelta: Float = 0.35
}

private struct ClusterGridKey: Hashable, Comparable {
    let x: Int
    let y: Int

    static func < (lhs: ClusterGridKey, rhs: ClusterGridKey) -> Bool {
        lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }
}

private struct MarkerPayload {
    let id: Int
    let clusterMemberIDs: [Int]?
}

fileprivate struct MarkerInputSignature: Equatable {
    let id: Int
    struct Coordinate: Equatable {
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
    }

    let coordinate: Coordinate
    let title: String
    let emoji: String
    let isSelected: Bool
    let clusterMemberIDs: [Int]?

    init(
        id: Int,
        coordinate: CLLocationCoordinate2D,
        title: String,
        emoji: String,
        isSelected: Bool,
        clusterMemberIDs: [Int]? = nil
    ) {
        self.id = id
        self.coordinate = Coordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        self.title = title
        self.emoji = emoji
        self.isSelected = isSelected
        self.clusterMemberIDs = clusterMemberIDs
    }
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
        emoji: String = "✦",
        isInteractive: Bool = true
    ) {
        self.init(
            markers: [
                GoogleMapMarkerData(
                    id: 0,
                    coordinate: coordinate,
                    title: title,
                    emoji: emoji
                )
            ],
            center: coordinate,
            zoom: 15,
            centerRequestID: 0,
            isInteractive: isInteractive,
            selectedID: nil,
            onSelect: { _ in },
            onDeselect: {}
        )
    }
}

private enum MarkerIconRenderer {
    private static let emojiCache = NSCache<NSString, UIImage>()

    static let cluster: UIImage = {
        let size = MarkerInteractionMetrics.clusterHitSize
        let dotSize: CGFloat = 12
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let dotRect = CGRect(
                x: (size - dotSize) / 2,
                y: (size - dotSize) / 2,
                width: dotSize,
                height: dotSize
            )
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.22).cgColor
            )
            UIColor.white.setFill()
            UIBezierPath(ovalIn: dotRect).fill()
        }
    }()

    static func emoji(_ emoji: String, isSelected: Bool) -> UIImage {
        let cacheKey = "\(emoji)-\(isSelected)"
        if let cached = emojiCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let size = MarkerInteractionMetrics.hitSize
        let visibleSize: CGFloat = isSelected ? 50 : 42
        let inset = (size - visibleSize) / 2
        let bubbleRect = CGRect(x: inset, y: inset, width: visibleSize, height: visibleSize)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 5,
                color: UIColor.black.withAlphaComponent(0.16).cgColor
            )
            (isSelected ? UIColor.white : UIColor.white.withAlphaComponent(0.88)).setFill()
            UIBezierPath(ovalIn: bubbleRect).fill()

            UIColor.white.setStroke()
            let borderPath = UIBezierPath(ovalIn: bubbleRect.insetBy(dx: 0.5, dy: 0.5))
            borderPath.lineWidth = isSelected ? 3 : 1
            borderPath.stroke()

            let font = UIFont.systemFont(ofSize: isSelected ? 24 : 19)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.label,
            ]
            let textSize = (emoji as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: bubbleRect.midX - textSize.width / 2,
                y: bubbleRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            (emoji as NSString).draw(in: textRect, withAttributes: attributes)
        }
        emojiCache.setObject(image, forKey: cacheKey as NSString)
        return image
    }
}
