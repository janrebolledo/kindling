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
)

struct Item: Decodable, Identifiable {
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
}
