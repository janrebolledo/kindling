//
//  OpenStreetMapHours.swift
//  roundup
//

import CoreLocation
import Foundation
import os

let openStreetMapLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "kindling",
    category: "OpenStreetMapHours"
)

struct OpenStreetMapHoursRow: Identifiable, Sendable {
    let id: Int
    let day: String
    let hours: String
}

struct OpenStreetMapHours: Sendable {
    let rawValue: String
    let rows: [OpenStreetMapHoursRow]
    let schedule: [OpenStreetMapDaySchedule]
    let sourceURL: URL

    var status: OpenStatus? {
        OpenStreetMapHoursParser.status(for: schedule)
    }
}

struct OpenStreetMapDaySchedule: Sendable {
    let weekday: Int // Calendar weekday: 1 = Sunday … 7 = Saturday
    let intervals: [OpenStreetMapInterval]
}

struct OpenStreetMapInterval: Sendable {
    let start: Int
    let end: Int
}

actor OpenStreetMapHoursService {
    static let shared = OpenStreetMapHoursService()

    private struct NominatimPlace: Decodable {
        let osmType: String?
        let osmID: Int?
        let name: String?
        let displayName: String?
        let lat: String?
        let lon: String?
        let extratags: [String: String]?

        enum CodingKeys: String, CodingKey {
            case osmType = "osm_type"
            case osmID = "osm_id"
            case name
            case displayName = "display_name"
            case lat
            case lon
            case extratags
        }
    }

    private var cache: [String: OpenStreetMapHours] = [:]
    private var misses = Set<String>()
    private var lastRequestDate: Date?

    func lookup(name: String, latitude: Double, longitude: Double) async -> OpenStreetMapHours? {
        let key = cacheKey(name: name, latitude: latitude, longitude: longitude)
        if let cached = cache[key] {
            openStreetMapLogger.debug(
                "Cache hit for venue=\(name, privacy: .private(mask: .hash))"
            )
            return cached
        }
        if misses.contains(key) {
            openStreetMapLogger.debug(
                "Negative cache hit for venue=\(name, privacy: .private(mask: .hash))"
            )
            return nil
        }

        openStreetMapLogger.debug(
            "Lookup started venue=\(name, privacy: .private(mask: .hash)) latitude=\(latitude, privacy: .private(mask: .hash)) longitude=\(longitude, privacy: .private(mask: .hash))"
        )

        await waitForRateLimit()
        guard !Task.isCancelled else {
            openStreetMapLogger.debug("Lookup cancelled before request")
            return nil
        }

        guard let url = makeURL(name: name, latitude: latitude, longitude: longitude) else {
            openStreetMapLogger.error("Could not construct Nominatim URL")
            misses.insert(key)
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Kindling/1.0 (https://getkindl.ing)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        lastRequestDate = Date()
        openStreetMapLogger.debug("Sending Nominatim search request")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                openStreetMapLogger.error("Nominatim returned HTTP status \(statusCode)")
                misses.insert(key)
                return nil
            }

            let places = try JSONDecoder().decode([NominatimPlace].self, from: data)
            let placesWithHours = places.filter {
                guard let hours = $0.extratags?["opening_hours"] else { return false }
                return !hours.isEmpty
            }
            openStreetMapLogger.debug(
                "Nominatim returned places=\(places.count) places_with_hours=\(placesWithHours.count)"
            )
            guard let place = bestMatch(
                places,
                name: name,
                latitude: latitude,
                longitude: longitude
            ),
            let rawHours = place.extratags?["opening_hours"],
            let parsed = OpenStreetMapHoursParser.parse(rawHours),
            let osmType = place.osmType,
            let osmID = place.osmID,
            let sourceURL = URL(string: "https://www.openstreetmap.org/\(osmType)/\(osmID)") else {
                openStreetMapLogger.debug(
                    "No usable OSM hours match for venue=\(name, privacy: .private(mask: .hash))"
                )
                misses.insert(key)
                return nil
            }

            let hours = OpenStreetMapHours(
                rawValue: rawHours,
                rows: parsed.rows,
                schedule: parsed.schedule,
                sourceURL: sourceURL
            )
            cache[key] = hours
            openStreetMapLogger.info(
                "Hours resolved venue=\(name, privacy: .private(mask: .hash)) raw_hours=\(rawHours, privacy: .public)"
            )
            return hours
        } catch {
            openStreetMapLogger.error(
                "Lookup failed error=\(String(describing: error), privacy: .public)"
            )
            misses.insert(key)
            return nil
        }
    }

    private func waitForRateLimit() async {
        guard let lastRequestDate else { return }
        let elapsed = Date().timeIntervalSince(lastRequestDate)
        let delay = max(0, 1.0 - elapsed)
        guard delay > 0 else { return }
        openStreetMapLogger.debug("Rate limiting request delay=\(delay, privacy: .public)s")
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func makeURL(name: String, latitude: Double, longitude: Double) -> URL? {
        let radius = 0.003
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "extratags", value: "1"),
            URLQueryItem(name: "addressdetails", value: "0"),
            URLQueryItem(
                name: "viewbox",
                value: "\(longitude - radius),\(latitude + radius),\(longitude + radius),\(latitude - radius)"
            ),
            URLQueryItem(name: "bounded", value: "1"),
            URLQueryItem(name: "accept-language", value: "en"),
        ]
        return components?.url
    }

    private func cacheKey(name: String, latitude: Double, longitude: Double) -> String {
        let normalizedName = name.lowercased().filter { $0.isLetter || $0.isNumber }
        return "\(normalizedName)-\(Int(latitude * 10_000))\(Int(longitude * 10_000))"
    }

    private func bestMatch(
        _ places: [NominatimPlace],
        name: String,
        latitude: Double,
        longitude: Double
    ) -> NominatimPlace? {
        let normalizedName = normalize(name)
        return places
            .compactMap { place -> (NominatimPlace, Double, Bool)? in
                guard let rawHours = place.extratags?["opening_hours"],
                      !rawHours.isEmpty,
                      let placeLatitude = place.lat.flatMap(Double.init),
                      let placeLongitude = place.lon.flatMap(Double.init) else {
                    return nil
                }

                let distance = distanceInMeters(
                    latitude: latitude,
                    longitude: longitude,
                    otherLatitude: placeLatitude,
                    otherLongitude: placeLongitude
                )
                guard distance <= 300 else { return nil }

                let normalizedPlaceName = normalize(place.name ?? place.displayName ?? "")
                let nameMatches = normalizedPlaceName == normalizedName
                    || normalizedPlaceName.contains(normalizedName)
                    || normalizedName.contains(normalizedPlaceName)
                return (place, distance, nameMatches)
            }
            .sorted {
                if $0.2 != $1.2 { return $0.2 }
                return $0.1 < $1.1
            }
            .first.map { match in
                openStreetMapLogger.debug(
                    "Candidate matched name=\(match.0.name ?? "unknown", privacy: .private(mask: .hash)) distance_meters=\(match.1, privacy: .public) name_match=\(match.2, privacy: .public)"
                )
                return match.0
            }
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func distanceInMeters(
        latitude: Double,
        longitude: Double,
        otherLatitude: Double,
        otherLongitude: Double
    ) -> Double {
        let first = CLLocation(latitude: latitude, longitude: longitude)
        let second = CLLocation(latitude: otherLatitude, longitude: otherLongitude)
        return first.distance(from: second)
    }
}

private enum OpenStreetMapHoursParser {
    nonisolated private static let dayNames = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]
    nonisolated private static let dayCodes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    nonisolated private static let timeRangeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\b"#
    )
    struct ParsedSchedule {
        let rows: [OpenStreetMapHoursRow]
        let schedule: [OpenStreetMapDaySchedule]
    }

    nonisolated static func parse(_ rawValue: String) -> ParsedSchedule? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var intervals = Array(repeating: [OpenStreetMapInterval](), count: 8)
        if trimmed == "24/7" {
            for weekday in 1...7 { intervals[weekday] = [OpenStreetMapInterval(start: 0, end: 1440)] }
        } else {
            for rawRule in trimmed.components(separatedBy: ";") {
                parseRule(rawRule, into: &intervals)
            }
        }

        let schedule = (1...7).map { weekday in
            OpenStreetMapDaySchedule(weekday: weekday, intervals: intervals[weekday])
        }
        let rows = [2, 3, 4, 5, 6, 7, 1].map { weekday in
            let day = schedule[weekday - 1]
            return OpenStreetMapHoursRow(
                id: day.weekday,
                day: dayNames[day.weekday - 1],
                hours: formattedIntervals(day.intervals)
            )
        }
        return ParsedSchedule(rows: rows, schedule: schedule)
    }

    nonisolated static func status(for schedule: [OpenStreetMapDaySchedule]) -> OpenStatus? {
        guard schedule.count == 7 else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        let today = schedule[weekday - 1]
        for interval in today.intervals where nowMinutes >= interval.start && nowMinutes < interval.end {
            if interval.start == 0 && interval.end == 1440 {
                return OpenStatus(isOpen: true, detail: "Open 24 hours")
            }
            return OpenStatus(isOpen: true, detail: "Closes at \(formatTime(interval.end % 1440))")
        }

        let previousWeekday = weekday == 1 ? 7 : weekday - 1
        let previous = schedule[previousWeekday - 1]
        for interval in previous.intervals where interval.end > 1440 {
            let adjustedEnd = interval.end - 1440
            if nowMinutes < adjustedEnd {
                return OpenStatus(isOpen: true, detail: "Closes at \(formatTime(adjustedEnd))")
            }
        }

        for offset in 0...6 {
            let candidateWeekday = ((weekday - 1 + offset) % 7) + 1
            let candidate = schedule[candidateWeekday - 1]
            let firstFutureInterval = candidate.intervals.first {
                offset > 0 || $0.start > nowMinutes
            }
            guard let interval = firstFutureInterval else { continue }
            let dayLabel = offset == 0 ? "" : "\(dayNames[candidateWeekday - 1]) "
            return OpenStatus(
                isOpen: false,
                detail: "Opens \(dayLabel)at \(formatTime(interval.start))"
            )
        }

        return OpenStatus(isOpen: false, detail: "Closed")
    }

    private nonisolated static func parseRule(
        _ rawRule: String,
        into intervals: inout [[OpenStreetMapInterval]]
    ) {
        var rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return }
        if let fallbackRange = rule.range(of: "||") {
            rule = String(rule[..<fallbackRange.lowerBound])
        }

        let lowercased = rule.lowercased()
        let days = parseDays(from: rule)
        if days == nil, lowercased.contains("ph") || lowercased.contains("sh") {
            return
        }
        let targetDays = days ?? Array(1...7)

        if lowercased.contains("off") || lowercased.contains("closed") {
            for weekday in targetDays { intervals[weekday].removeAll() }
            return
        }

        let range = NSRange(rule.startIndex..., in: rule)
        let matches = timeRangeRegex.matches(in: rule, range: range)
        guard !matches.isEmpty else { return }

        for match in matches {
            guard let matchRange = Range(match.range, in: rule),
                  let startHour = Int(rule[Range(match.range(at: 1), in: rule)!]),
                  let startMinute = Int(rule[Range(match.range(at: 2), in: rule)!]),
                  let endHour = Int(rule[Range(match.range(at: 3), in: rule)!]),
                  let endMinute = Int(rule[Range(match.range(at: 4), in: rule)!]),
                  startHour <= 24,
                  endHour <= 24,
                  startMinute < 60,
                  endMinute < 60 else { continue }

            let start = startHour * 60 + startMinute
            let rawEnd = endHour * 60 + endMinute
            let end = rawEnd <= start ? rawEnd + 1440 : rawEnd
            guard start < 1440, end > start else { continue }
            _ = matchRange
            for weekday in targetDays {
                intervals[weekday].append(OpenStreetMapInterval(start: start, end: end))
            }
        }

        for weekday in targetDays {
            intervals[weekday].sort { $0.start < $1.start }
        }
    }

    private nonisolated static func parseDays(from rule: String) -> [Int]? {
        let range = NSRange(rule.startIndex..., in: rule)
        let matches = dayCodes.compactMap { code -> (String, Int)? in
            let pattern = "\\b\(code)\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: rule, range: range) else { return nil }
            return (code, match.range.location)
        }.sorted { $0.1 < $1.1 }

        guard !matches.isEmpty else { return nil }
        let values = matches.map { dayCodes.firstIndex(of: $0.0)! }
        if matches.count == 2 {
            let between = rule.index(
                rule.startIndex,
                offsetBy: matches[0].1
            )..<rule.index(rule.startIndex, offsetBy: matches[1].1)
            if rule[between].contains("-") {
                let first = calendarWeekday(forDayCodeIndex: values[0])
                let last = calendarWeekday(forDayCodeIndex: values[1])
                var result: [Int] = []
                var current = first
                repeat {
                    result.append(current)
                    if current == last { break }
                    current = current == 7 ? 1 : current + 1
                } while true
                return result
            }
        }
        return values.map(calendarWeekday(forDayCodeIndex:))
    }

    private nonisolated static func calendarWeekday(forDayCodeIndex index: Int) -> Int {
        // OSM starts on Monday; Calendar starts on Sunday.
        return index == 6 ? 1 : index + 2
    }

    private nonisolated static func formattedIntervals(_ intervals: [OpenStreetMapInterval]) -> String {
        guard !intervals.isEmpty else { return "Closed" }
        if intervals.contains(where: { $0.start == 0 && $0.end == 1440 }) {
            return "Open 24 hours"
        }
        return intervals.map {
            "\(formatTime($0.start))–\(formatTime($0.end % 1440))"
        }.joined(separator: ", ")
    }

    private nonisolated static func formatTime(_ minutes: Int) -> String {
        let normalized = minutes == 1440 ? 0 : minutes
        let hour = normalized / 60
        let minute = normalized % 60
        let suffix = hour >= 12 ? "PM" : "AM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%d:%02d %@", displayHour, minute, suffix)
    }
}
