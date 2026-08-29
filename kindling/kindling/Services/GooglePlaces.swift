import CoreLocation
import Foundation
import Supabase

nonisolated struct GooglePlaceDetails: Codable, Sendable {
    let id: String
    let name: String?
    let priceLevel: String?
    let latitude: Double?
    let longitude: Double?
    let formattedAddress: String?
    let weekdayDescriptions: [String]
    let openNow: Bool?
    let photoUrl: String?
    let photoAttributions: [String]
    let googleMapsUri: String?

    /// Returns the city and abbreviated state from a U.S. formatted address.
    /// Google commonly returns values such as "CA 90015", so the city is the
    /// address component immediately before the state component.
    var cityStateLabel: String? {
        guard let formattedAddress else { return nil }

        let components = formattedAddress
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard components.count >= 2 else { return nil }

        for index in stride(from: components.count - 1, through: 1, by: -1) {
            let stateCandidate = components[index]
                .replacingOccurrences(
                    of: "\\s+\\d{5}(?:-\\d{4})?$",
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let stateAbbreviation = Self.usStateAbbreviations[stateCandidate.uppercased()]
            else { continue }

            let city = components[index - 1]
            guard !city.isEmpty else { return nil }
            return "\(city), \(stateAbbreviation)"
        }

        return nil
    }

    var priceLevelLabel: String? {
        switch priceLevel {
        case "PRICE_LEVEL_FREE": return "Free"
        case "PRICE_LEVEL_INEXPENSIVE": return "$"
        case "PRICE_LEVEL_MODERATE": return "$$"
        case "PRICE_LEVEL_EXPENSIVE": return "$$$"
        case "PRICE_LEVEL_VERY_EXPENSIVE": return "$$$$"
        default: return nil
        }
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static let usStateAbbreviations: [String: String] = [
        "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR",
        "CALIFORNIA": "CA", "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE",
        "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI", "IDAHO": "ID",
        "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA", "KANSAS": "KS",
        "KENTUCKY": "KY", "LOUISIANA": "LA", "MAINE": "ME", "MARYLAND": "MD",
        "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN", "MISSISSIPPI": "MS",
        "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE", "NEVADA": "NV",
        "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM", "NEW YORK": "NY",
        "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH", "OKLAHOMA": "OK",
        "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI", "SOUTH CAROLINA": "SC",
        "SOUTH DAKOTA": "SD", "TENNESSEE": "TN", "TEXAS": "TX", "UTAH": "UT",
        "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA", "WEST VIRGINIA": "WV",
        "WISCONSIN": "WI", "WYOMING": "WY", "DISTRICT OF COLUMBIA": "DC",
        "AL": "AL", "AK": "AK", "AZ": "AZ", "AR": "AR", "CA": "CA", "CO": "CO",
        "CT": "CT", "DE": "DE", "FL": "FL", "GA": "GA", "HI": "HI", "ID": "ID",
        "IL": "IL", "IN": "IN", "IA": "IA", "KS": "KS", "KY": "KY", "LA": "LA",
        "ME": "ME", "MD": "MD", "MA": "MA", "MI": "MI", "MN": "MN", "MS": "MS",
        "MO": "MO", "MT": "MT", "NE": "NE", "NV": "NV", "NH": "NH", "NJ": "NJ",
        "NM": "NM", "NY": "NY", "NC": "NC", "ND": "ND", "OH": "OH", "OK": "OK",
        "OR": "OR", "PA": "PA", "RI": "RI", "SC": "SC", "SD": "SD", "TN": "TN",
        "TX": "TX", "UT": "UT", "VT": "VT", "VA": "VA", "WA": "WA", "WV": "WV",
        "WI": "WI", "WY": "WY", "DC": "DC",
    ]

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
