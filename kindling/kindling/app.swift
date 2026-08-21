//
//  roundupApp.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import GoogleMaps
import Supabase
import SwiftUI

private struct IsAuthenticatedKey: EnvironmentKey {
    static var defaultValue: Bool = false

}

extension EnvironmentValues {
    var isAuthenticated: Bool {
        get { self[IsAuthenticatedKey.self] }
        set { self[IsAuthenticatedKey.self] = newValue }
    }
}

@main
struct AppEntry: App {
    @State private var onboardingCompleted = false
    @State private var authenticated = false
    @State private var userSettings = UserSettings()
    @State private var directionsCache = DirectionsCache()
    @State private var screenshotIndexing = ScreenshotIndexingController.shared

    var body: some Scene {

        WindowGroup {
            Group {
                if !authenticated {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .environment(userSettings)
            .environment(directionsCache)
            .environment(screenshotIndexing)
            .environment(\.isAuthenticated, authenticated)
            .task {
                for await state in supabase.auth.authStateChanges {
                    if state.event == .userUpdated {
                        userSettings.refreshDisplayName()
                    } else if [.initialSession, .signedIn, .signedOut].contains(
                        state.event
                    ) {
                        if let session = state.session {
                            authenticated = !session.isExpired
                            Task { await userSettings.load() }
                        } else {
                            authenticated = false
                            userSettings.reset()
                        }
                    }
                }
            }
        }
    }

    init() {
        let configuredKey = [
            Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
            ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty && !$0.contains("$(") }

        if let key = configuredKey {
            GMSServices.provideAPIKey(key)
        }
    }
}
