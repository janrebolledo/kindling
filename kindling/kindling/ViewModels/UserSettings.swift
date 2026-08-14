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

    func reset() {
        transportType = .driving
    }

    func load() async {
        guard let userID = supabase.auth.currentUser?.id else {
            await MainActor.run { reset() }
            return
        }
        do {
            let rows: [UserData] = try await supabase
                .from("user_data")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
            if let raw = rows.first?.preferred_transport_type,
               let parsed = TransportType(rawValue: raw) {
                await MainActor.run { transportType = parsed }
            } else {
                await MainActor.run { reset() }
            }
        } catch {}
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
