//
//  UserSettings.swift
//  kindling
//
//  Created by Jan Rebolledo on 6/16/26.
//

import Foundation
import Observation
import Supabase

enum InferenceProvider: String, CaseIterable, Identifiable {
    case cloud
    case appleFoundationModels

    static let defaultsKey = "inferenceProvider"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloud: return "kindling cloud"
        case .appleFoundationModels: return "on this iPhone"
        }
    }
}

@Observable
class UserSettings {
    var transportType: TransportType = .driving
    var displayName: String = "you"
    var inferenceProvider: InferenceProvider = {
        guard let raw = UserDefaults.standard.string(forKey: InferenceProvider.defaultsKey)
        else { return .cloud }
        return InferenceProvider(rawValue: raw) ?? .cloud
    }() {
        didSet {
            UserDefaults.standard.set(
                inferenceProvider.rawValue,
                forKey: InferenceProvider.defaultsKey
            )
        }
    }

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
