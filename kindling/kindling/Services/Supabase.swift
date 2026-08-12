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
    /// capitalized email prefix.
    var displayName: String {
        for key in ["display_name", "full_name", "name"] {
            if let value = userMetadata[key]?.stringValue,
                !value.isEmpty
            {
                return value
            }
        }
        let prefix = email?.split(separator: "@").first.map(String.init) ?? "you"
        return prefix.prefix(1).uppercased() + prefix.dropFirst()
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
    let duration: String?
    let pricing: Int?
    let date: String?
    let time: String?
    let venue: String?
    let created_at: String?
    let open_hours: [String]?
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
