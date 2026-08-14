//
//  DirectionsCache.swift
//  kindling
//

import MapKit
import Observation

@Observable
final class DirectionsCache {
    private var mapItems: [Int: MKMapItem] = [:]
    private var etas: [ETAKey: String] = [:]

    private struct ETAKey: Hashable {
        let ideaID: Int
        let transport: TransportType
    }

    func mapItem(for ideaID: Int) -> MKMapItem? {
        mapItems[ideaID]
    }

    func eta(for ideaID: Int, transport: TransportType) -> String? {
        etas[ETAKey(ideaID: ideaID, transport: transport)]
    }

    func store(mapItem: MKMapItem, for ideaID: Int) {
        mapItems[ideaID] = mapItem
    }

    func store(eta: String, for ideaID: Int, transport: TransportType) {
        etas[ETAKey(ideaID: ideaID, transport: transport)] = eta
    }
}
