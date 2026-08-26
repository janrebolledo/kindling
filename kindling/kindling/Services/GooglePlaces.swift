import CoreLocation
import Foundation
import Supabase

nonisolated struct GooglePlaceDetails: Codable, Sendable {
    let id: String
    let name: String?
    let latitude: Double?
    let longitude: Double?
    let formattedAddress: String?
    let weekdayDescriptions: [String]
    let openNow: Bool?
    let photoUrl: String?
    let photoAttributions: [String]
    let googleMapsUri: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    var hours: GooglePlaceHours? {
        guard !weekdayDescriptions.isEmpty else { return nil }
        return GooglePlaceHours(
            weekdayDescriptions: weekdayDescriptions,
            openNow: openNow
        )
    }
}

nonisolated struct GooglePlaceHours: Sendable {
    let weekdayDescriptions: [String]
    let openNow: Bool?
    var rows: [GooglePlaceHoursRow] {
        weekdayDescriptions.enumerated().map { index, description in
            let pieces = description.split(separator: ":", maxSplits: 1)
            return GooglePlaceHoursRow(
                id: index,
                day: pieces.first.map(String.init) ?? description,
                hours: pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : ""
            )
        }
    }

    var status: OpenStatus? {
        guard let openNow else { return resolveOpenStatus(from: weekdayDescriptions) }
        if openNow {
            if let detail = resolveOpenStatus(from: weekdayDescriptions), detail.isOpen {
                return OpenStatus(isOpen: true, detail: detail.detail)
            }
            return OpenStatus(isOpen: true, detail: "Open")
        }
        if let detail = resolveOpenStatus(from: weekdayDescriptions), !detail.isOpen {
            return OpenStatus(isOpen: false, detail: detail.detail)
        }
        return OpenStatus(isOpen: false, detail: "Closed")
    }
}

nonisolated struct GooglePlaceHoursRow: Identifiable, Sendable {
    let id: Int
    let day: String
    let hours: String
}

nonisolated struct GoogleRouteResponse: Codable, Sendable {
    let duration: String?
    let distanceMeters: Double?

    var formattedDuration: String? {
        guard let duration else { return nil }
        let rawDuration = duration.hasSuffix("s") ? String(duration.dropLast()) : duration
        let seconds = Int(Double(rawDuration) ?? 0)
        let minutes = max(1, Int(round(Double(seconds) / 60)))
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(minutes)m"
    }
}

actor GooglePlacesService {
    static let shared = GooglePlacesService()

    private var placeCache: [String: GooglePlaceDetails] = [:]
    private var placeRequests: [String: Task<GooglePlaceDetails?, Never>] = [:]
    private var routeCache: [String: String] = [:]
    private var routeRequests: [String: Task<String?, Never>] = [:]

    func details(for placeID: String) async -> GooglePlaceDetails? {
        let signpostID = KindlingProfiling.begin(KindlingProfiling.placeResolution)
        defer {
            KindlingProfiling.end(KindlingProfiling.placeResolution, id: signpostID)
        }

        if let cached = placeCache[placeID] { return cached }

        if let request = placeRequests[placeID] {
            return await request.value
        }

        let request = Task<GooglePlaceDetails?, Never> {
            let url = backendBaseURL.appendingPathComponent("places").appendingPathComponent(placeID)

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return try JSONDecoder().decode(GooglePlaceDetails.self, from: data)
            } catch {
                return nil
            }
        }
        placeRequests[placeID] = request

        let details = await request.value
        placeRequests[placeID] = nil
        if let details { placeCache[placeID] = details }
        return details
    }

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        transportType: TransportType
    ) async -> String? {
        let key = "\(origin.latitude),\(origin.longitude)|\(destination.latitude),\(destination.longitude)|\(transportType.rawValue)"
        if let cached = routeCache[key] { return cached }

        if let request = routeRequests[key] {
            return await request.value
        }

        let mode: String
        switch transportType {
        case .driving: mode = "DRIVE"
        case .cycling: mode = "BICYCLE"
        case .transit: mode = "TRANSIT"
        }

        let request = Task<String?, Never> {
            guard let url = URL(string: backendBaseURL.absoluteString + "/routes") else { return nil }
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let session = try? await supabase.auth.session {
                urlRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }
            urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: [
                "origin": ["latitude": origin.latitude, "longitude": origin.longitude],
                "destination": ["latitude": destination.latitude, "longitude": destination.longitude],
                "travelMode": mode,
            ])

            do {
                let (data, response) = try await URLSession.shared.data(for: urlRequest)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                let route = try JSONDecoder().decode(GoogleRouteResponse.self, from: data)
                return route.formattedDuration
            } catch {
                return nil
            }
        }
        routeRequests[key] = request

        let formattedDuration = await request.value
        routeRequests[key] = nil
        if let formattedDuration { routeCache[key] = formattedDuration }
        return formattedDuration
    }
}
