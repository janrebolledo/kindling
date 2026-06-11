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
