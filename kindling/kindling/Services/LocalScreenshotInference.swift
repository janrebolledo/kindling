import Foundation
import FoundationModels
import os

@Generable
private enum LocalExtractionStatus {
    case success
    case skipped
    case sensitive
}

@Generable
private struct LocalExtractedItem {
    @Guide(description: "Short display name for the activity or venue")
    var name: String?
    @Guide(description: "Exact restaurant, cafe, attraction, or event venue")
    var venue: String?
    @Guide(description: "City, neighborhood, or region")
    var location: String?
    @Guide(description: "Street address if explicitly present")
    var address: String?
    @Guide(description: "Date in YYYY-MM-DD format if present")
    var date: String?
    @Guide(description: "Time as written, if present")
    var time: String?
    @Guide(description: "Explicit activity or route length in miles, if present")
    var distanceMiles: Double?
    @Guide(description: "Explicit activity or route completion time, if present")
    var completionTime: String?
    @Guide(description: "One of: activity, event, food")
    var tag: String
    @Guide(description: "Specific activity category, such as restaurant or hike")
    var activityType: String?
    @Guide(description: "A single emoji representing the activity")
    var activityEmoji: String?
    @Guide(description: "One concise factual sentence describing the idea")
    var description: String?
    @Guide(description: "The most useful recommendation or quoted detail")
    var highlights: String?
    @Guide(description: "Short OCR excerpts that support the highlight")
    var highlightSources: [String]?
}

@Generable
private struct LocalExtraction {
    var status: LocalExtractionStatus
    @Guide(description: "Why content was skipped or marked sensitive")
    var reason: String?
    var item: LocalExtractedItem?
}

struct LocalExtractionResult: Encodable {
    let id: String
    let data: LocalExtractionData
}

struct LocalExtractionData: Encodable {
    let status: String
    let reason: String?
    let item: LocalExtractionItem?
}

struct LocalExtractionItem: Encodable {
    let name: String?
    let venue: String?
    let location: String?
    let address: String?
    let date: String?
    let time: String?
    let distance_miles: Double?
    let completion_time: String?
    let tag: String
    let activity_type: String?
    let activity_emoji: String?
    let description: String?
    let highlights: String?
    let highlights_sources: [String]?
}

enum LocalScreenshotInference {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "kindling",
        category: "LocalScreenshotInference"
    )

    static var isAvailable: Bool {
        let availability = SystemLanguageModel.default.availability
        let available: Bool
        if case .available = availability {
            available = true
        } else {
            available = false
        }

        return available
    }

    static func extract(_ screenshots: [Upload]) async throws -> [LocalExtractionResult] {
        let session = LanguageModelSession(instructions: """
            You organize screenshot OCR into saveable outing ideas. Extract only restaurants,
            cafes, events, attractions, or activities the user may want to visit. OCR may come
            from social posts, messages, Apple Maps place cards, review apps, or other apps; an
            Apple Maps place card is valid source material when it identifies a useful place.
            Mark financial, medical, authentication, or other private content sensitive. Skip
            content without a useful idea. Never invent a venue, address, date, or time. Use null
            when absent. For activities, copy an explicitly shown route length and completion
            time into the activity metric fields; never use an event start time or business hours.
            """)

        var results: [LocalExtractionResult] = []
        results.reserveCapacity(screenshots.count)
        for (index, screenshot) in screenshots.enumerated() {
            let textLength = screenshot.text.utf8.count
            if screenshot.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.error(
                    "Screenshot \(index + 1)/\(screenshots.count) has empty OCR text, id=\(screenshot.id, privacy: .private(mask: .hash)), OCR bytes=\(textLength)"
                )
            }

            let response: LanguageModelSession.Response<LocalExtraction>
            do {
                response = try await session.respond(
                    to: "Analyze this OCR text:\n\(screenshot.text)",
                    generating: LocalExtraction.self
                )
            } catch {
                logger.error(
                    "Local extraction failed for screenshot \(index + 1)/\(screenshots.count), id=\(screenshot.id, privacy: .private(mask: .hash)): \(String(describing: error), privacy: .public)"
                )
                throw error
            }

            let output = response.content
            let item = output.item.map {
                LocalExtractionItem(
                    name: $0.name,
                    venue: $0.venue,
                    location: $0.location,
                    address: $0.address,
                    date: $0.date,
                    time: $0.time,
                    distance_miles: $0.distanceMiles,
                    completion_time: $0.completionTime,
                    tag: ["activity", "event", "food"].contains($0.tag.lowercased()) ? $0.tag.lowercased() : "activity",
                    activity_type: $0.activityType,
                    activity_emoji: $0.activityEmoji,
                    description: $0.description,
                    highlights: $0.highlights,
                    highlights_sources: $0.highlightSources
                )
            }
            results.append(
                LocalExtractionResult(
                    id: screenshot.id,
                    data: LocalExtractionData(
                        status: String(describing: output.status),
                        reason: output.reason,
                        item: item
                    )
                )
            )
        }
        return results
    }
}
