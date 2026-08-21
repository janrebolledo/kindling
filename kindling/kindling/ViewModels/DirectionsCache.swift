//
//  DirectionsCache.swift
//  kindling
//

import Observation

@Observable
final class DirectionsCache {
    private var etas: [ETAKey: String] = [:]

    private struct ETAKey: Hashable {
        let ideaID: Int
        let transport: TransportType
    }

    func eta(for ideaID: Int, transport: TransportType) -> String? {
        etas[ETAKey(ideaID: ideaID, transport: transport)]
    }

    func store(eta: String, for ideaID: Int, transport: TransportType) {
        etas[ETAKey(ideaID: ideaID, transport: transport)] = eta
    }
}
