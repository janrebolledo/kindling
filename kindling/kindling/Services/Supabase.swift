//
//  Supabase.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://bfbaqyhyxergcpsyhzcc.supabase.co")!,
    supabaseKey: "sb_publishable_Q3wc-o2JVqIYPQVw47306w_zpKAE0VI",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            emitLocalSessionAsInitialSession: true
        )
    )
)

extension User {
    /// The user's display name, derived from auth metadata
    /// (`display_name`, then `full_name`, then `name`), falling back to the
    /// email prefix. Always lowercase to match the rest of the UI.
    var displayName: String {
        for key in ["display_name", "full_name", "name"] {
            if let value = userMetadata[key]?.stringValue,
                !value.isEmpty
            {
                return value.lowercased()
            }
        }
        let prefix = email?.split(separator: "@").first.map(String.init) ?? "you"
        return prefix.lowercased()
    }
}

struct Item: Codable, Identifiable {
    let id: Int
    let name: String?
    let type: String?
    let description: String?
    let media_url: String?
    let address: String?
    let location: String?
    let location_type: String?
    let location_emoji: String?
    let duration: String?
    let pricing: Int?
    let date: String?
    let time: String?
    let venue: String?
    let place_id: String?
    let place_provider: String?
    let created_at: String?
    let open_hours: [String]?

    var locationTypeLabel: String? {
        let label = [location_emoji, location_type]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return label.isEmpty ? nil : label
    }
}

struct collection: Encodable, Identifiable {
    let id: Int
    let name: String?
    let emoji: String?
    let user_id: UUID?
}

struct collection_item: Encodable, Decodable, Identifiable {
    let id: Int
    let created_at: String?
    let local_id: String
    let idea_id: Int
    let user_id: UUID
    let collection_id: Int?
}

struct UserData: Decodable {
    let id: Int
    let user_id: UUID
    let parsed_screenshot_ids: [String]
    let created_at: String?
    let preferred_transport_type: String?
    let username: String?
}
