//
//  ProfilingSignposts.swift
//  kindling
//
//  Temporary, low-overhead signposts for the P0 performance attribution pass.
//  Remove this file and its call sites after the next Instruments run.
//

import Foundation
import os

enum KindlingProfiling {
    nonisolated static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "kindling",
        category: "Performance"
    )

    nonisolated static let collectionLoad: StaticString = "Collection loading"
    nonisolated static let screenshotScan: StaticString = "Screenshot indexing"
    nonisolated static let screenshotEnumeration: StaticString = "Screenshot enumeration"
    nonisolated static let placeResolution: StaticString = "Place resolution"
    nonisolated static let cardImageLoad: StaticString = "Card image load"
    nonisolated static let cardPlaceDetails: StaticString = "Card place details"
    nonisolated static let mapUpdateUIView: StaticString = "GoogleMapView.updateUIView"
    nonisolated static let mapUpdateMarkers: StaticString = "Coordinator.updateMarkers"

    @inline(__always)
    nonisolated static func begin(_ name: StaticString) -> OSSignpostID {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        return signpostID
    }

    @inline(__always)
    nonisolated static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
