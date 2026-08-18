//
//  UsernameBootstrap.swift
//  kindling
//
//  Generates a default username from the email prefix the first time an
//  account signs in. Shared by Apple and email auth.
//

import Foundation
import Supabase

func ensureUsernameExists() async {
    guard let user = supabase.auth.currentUser else { return }

    do {
        let rows: [UsernameRow] =
            try await supabase
            .from("user_data")
            .select("username")
            .eq("user_id", value: user.id)
            .execute()
            .value
        if let existing = rows.first?.username, !existing.isEmpty { return }
    } catch {
        dump(error)
        return
    }

    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
    var base = (user.email?.split(separator: "@").first.map(String.init) ?? "user")
        .lowercased()
        .filter { allowed.contains($0) }
    if base.count < 3 { base += "user" }
    base = String(base.prefix(20))

    func candidate(_ index: Int) -> String {
        guard index > 0 else { return base }
        let suffix = String(index)
        let trimmed = String(base.prefix(20 - suffix.count))
        return trimmed + suffix
    }

    for attempt in 0...50 {
        let candidate =
            attempt <= 9 ? candidate(attempt) : candidate(Int.random(in: 100...9999))
        do {
            let available: Bool =
                try await supabase
                .rpc("is_username_available", params: ["candidate": candidate])
                .execute()
                .value
            if !available { continue }

            try await supabase
                .from("user_data")
                .upsert(
                    UsernameInsert(user_id: user.id, username: candidate),
                    onConflict: "user_id"
                )
                .execute()
            return
        } catch let error as PostgrestError where error.code == "23505" {
            continue
        } catch {
            dump(error)
            return
        }
    }
}

private struct UsernameRow: Decodable {
    let username: String?
}

private struct UsernameInsert: Encodable {
    let user_id: UUID
    let username: String
}
