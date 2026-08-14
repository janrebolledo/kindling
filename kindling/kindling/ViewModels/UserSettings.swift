//
//  UserSettings.swift
//  kindling
//
//  Created by Jan Rebolledo on 6/16/26.
//

import Observation
import Supabase

@Observable
class UserSettings {
    var transportType: TransportType = .driving
    var displayName: String = "you"

    func reset() {
        transportType = .driving
        displayName = "you"
    }

    func refreshDisplayName() {
        displayName = supabase.auth.currentUser?.displayName ?? "you"
    }

    func load() async {
        guard let user = supabase.auth.currentUser else {
            await MainActor.run { reset() }
            return
        }
        let name = user.displayName
        do {
            let rows: [UserData] = try await supabase
                .from("user_data")
                .select()
                .eq("user_id", value: user.id)
                .execute()
                .value
            if let raw = rows.first?.preferred_transport_type,
               let parsed = TransportType(rawValue: raw) {
                await MainActor.run {
                    transportType = parsed
                    displayName = name
                }
            } else {
                await MainActor.run {
                    transportType = .driving
                    displayName = name
                }
            }
        } catch {
            await MainActor.run { displayName = name }
        }
    }

    func persistTransportType() async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let payload = TransportPreferencePayload(
            user_id: userID,
            preferred_transport_type: transportType.rawValue
        )
        do {
            try await supabase
                .from("user_data")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {}
    }
}
