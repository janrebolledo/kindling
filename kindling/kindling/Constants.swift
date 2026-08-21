//
//  Constants.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import SwiftUI

enum AnimationConstants {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let springFast = Animation.spring(response: 0.25, dampingFraction: 0.8)
}

enum LayoutConstants {
    static let heroHeight: CGFloat = 500
}

struct OpenStatus: Sendable {
    let isOpen: Bool
    let detail: String
}

private let timeRegex = try! NSRegularExpression(pattern: #"\d{1,2}(?::\d{2})?\s*[AaPp][Mm]"#)

private func extractTimes(from str: String) -> (open: String, close: String)? {
    let range = NSRange(str.startIndex..., in: str)
    let matches = timeRegex.matches(in: str, range: range)
    guard matches.count >= 2,
          let openRange = Range(matches.first!.range, in: str),
          let closeRange = Range(matches.last!.range, in: str) else { return nil }
    return (String(str[openRange]), String(str[closeRange]))
}

/// Parses today's entry from a Google Places `weekdayDescriptions` array and returns
/// whether the place is currently open and the next transition time (e.g. "Closes at 4:00 PM").
nonisolated func resolveOpenStatus(from openHours: [String]) -> OpenStatus? {
    let calendar = Calendar.current
    let now = Date()
    let weekday = calendar.component(.weekday, from: now) // 1=Sun … 7=Sat
    let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    let todayName = dayNames[weekday - 1]

    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")

    let toMinutes: (Date) -> Int = { d in
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    let parseTime: (String) -> Date? = { s in
        for format in ["h:mm a", "h a"] {
            fmt.dateFormat = format
            if let d = fmt.date(from: s.trimmingCharacters(in: .whitespaces)) { return d }
        }
        return nil
    }

    guard let entry = openHours.first(where: { $0.hasPrefix(todayName) }),
          let colonRange = entry.range(of: ": ") else { return nil }

    let hoursStr = String(entry[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

    if hoursStr.lowercased() == "open 24 hours" { return OpenStatus(isOpen: true, detail: "Open 24 hours") }

    let nowMin = toMinutes(now)

    // Try to match today's open periods (skip if "Closed")
    if hoursStr.lowercased() != "closed" {
        for period in hoursStr.components(separatedBy: ", ") {
            guard let (openStr, closeStr) = extractTimes(from: period),
                  let openTime = parseTime(openStr),
                  let closeTime = parseTime(closeStr) else { continue }
            let openMin = toMinutes(openTime)
            var closeMin = toMinutes(closeTime)
            if closeMin <= openMin { closeMin += 1440 }
            if nowMin >= openMin && nowMin < closeMin {
                return OpenStatus(isOpen: true, detail: "Closes at \(closeStr)")
            } else if nowMin < openMin {
                return OpenStatus(isOpen: false, detail: "Opens at \(openStr)")
            }
        }
    }

    // Today is closed or all periods have passed — scan ahead up to 6 days
    for daysAhead in 1...6 {
        let nextWeekday = (weekday - 1 + daysAhead) % 7
        let nextName = dayNames[nextWeekday]
        guard let nextEntry = openHours.first(where: { $0.hasPrefix(nextName) }),
              let nextColon = nextEntry.range(of: ": ") else { continue }
        let nextHours = String(nextEntry[nextColon.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard nextHours.lowercased() != "closed",
              nextHours.lowercased() != "open 24 hours" else {
            if nextHours.lowercased() == "open 24 hours" {
                let dayLabel = daysAhead == 1 ? "" : "\(nextName) "
                return OpenStatus(isOpen: false, detail: "Opens \(dayLabel)24 hours")
            }
            continue
        }
        if let (openStr, _) = extractTimes(from: nextHours) {
            let dayLabel = daysAhead == 1 ? "" : "\(nextName) "
            return OpenStatus(isOpen: false, detail: "Opens \(dayLabel)at \(openStr)")
        }
    }
    return OpenStatus(isOpen: false, detail: "Closed")
}
