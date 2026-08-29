//
//  OnboardingDraftCache.swift
//  kindling
//
//  Persists the enriched draft collection_items produced during onboarding so
//  that, if the user closes the app before signing up, their parsed items are
//  ready on the next launch. Cleared once the items are finalized server-side.
//

import Foundation

enum OnboardingDraftCache {
    private static let key = "onboardingDraftItems"

    static func save(_ items: [ItemWrapper]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func load() -> [ItemWrapper] {
        guard let data = UserDefaults.standard.data(forKey: key),
            let items = try? JSONDecoder().decode([ItemWrapper].self, from: data)
        else {
            return []
        }
        return items
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// A short-lived handoff from onboarding to the first authenticated home
/// screen. The server remains authoritative; this only fills the gap while
/// the post-sign-up collection request is in flight.
enum OnboardingHomeCache {
    private struct Entry: Codable {
        let userID: UUID
        let savedAt: Date
        let items: [ItemWrapper]
    }

    private struct PendingEntry: Codable {
        let savedAt: Date
        let items: [ItemWrapper]
    }

    private static let keyPrefix = "onboardingHomeCache."
    private static let pendingKey = "onboardingHomeCache.pending"
    private static let maxAge: TimeInterval = 10 * 60

    static func save(_ items: [ItemWrapper], for userID: UUID) {
        guard !items.isEmpty else {
            clear(for: userID)
            return
        }

        let entry = Entry(userID: userID, savedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: key(for: userID))
    }

    /// Saves the handoff before authentication completes, avoiding a race
    /// where the authenticated home view mounts before sign-up's finalizer.
    static func savePending(_ items: [ItemWrapper]) {
        guard !items.isEmpty else {
            clearPending()
            return
        }

        let entry = PendingEntry(savedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    static func load(for userID: UUID) -> [ItemWrapper] {
        if let data = UserDefaults.standard.data(forKey: key(for: userID)),
           let entry = try? JSONDecoder().decode(Entry.self, from: data)
        {
            guard entry.userID == userID, !isExpired(entry.savedAt) else {
                clear(for: userID)
                return []
            }
            return entry.items
        }

        // A successful auth can publish its session before the async
        // collection finalizer gets to persist the user-scoped entry.
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let pending = try? JSONDecoder().decode(PendingEntry.self, from: data)
        else {
            return []
        }

        guard !isExpired(pending.savedAt) else {
            clearPending()
            return []
        }

        save(pending.items, for: userID)
        clearPending()
        return pending.items
    }

    static func removeConfirmedItems(
        localIDs confirmedLocalIDs: Set<String>,
        for userID: UUID
    ) {
        guard !confirmedLocalIDs.isEmpty else { return }

        let remaining = load(for: userID).filter {
            !confirmedLocalIDs.contains($0.local_id)
        }
        if remaining.isEmpty {
            clear(for: userID)
        } else {
            save(remaining, for: userID)
        }
    }

    static func clear(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: userID))
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private static func key(for userID: UUID) -> String {
        "\(keyPrefix)\(userID.uuidString)"
    }

    private static func isExpired(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > maxAge
    }
}
