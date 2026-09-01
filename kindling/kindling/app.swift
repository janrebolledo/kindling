//
//  roundupApp.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import GoogleMaps
import PostHog
import Supabase
import SwiftUI

private struct IsAuthenticatedKey: EnvironmentKey {
    static var defaultValue: Bool = false

}

private enum AuthStatus: Equatable {
    case loading
    case signedIn
    case signedOut
}

extension EnvironmentValues {
    var isAuthenticated: Bool {
        get { self[IsAuthenticatedKey.self] }
        set { self[IsAuthenticatedKey.self] = newValue }
    }
}

@main
struct AppEntry: App {
    @State private var authStatus: AuthStatus = .loading
    @State private var userSettings = UserSettings()
    @State private var directionsCache = DirectionsCache()
    @State private var screenshotIndexing = ScreenshotIndexingController.shared

    var body: some Scene {

        WindowGroup {
            Group {
                switch authStatus {
                case .loading:
                    Color.clear
                        .ignoresSafeArea()
                case .signedOut:
                    OnboardingView()
                case .signedIn:
                    ContentView()
                }
            }
            .environment(userSettings)
            .environment(directionsCache)
            .environment(screenshotIndexing)
            .environment(\.isAuthenticated, authStatus == .signedIn)
            .task {
                for await state in supabase.auth.authStateChanges {
                    if state.event == .userUpdated {
                        userSettings.refreshDisplayName()
                        continue
                    }

                    switch state.event {
                    case .initialSession, .signedIn, .tokenRefreshed:
                        guard state.session != nil else {
                            authStatus = .signedOut
                            userSettings.reset()
                            continue
                        }

                        do {
                            // Be defensive if the SDK surfaces an expired
                            // cached session while it refreshes it. Ask for
                            // the session before deciding which root view to
                            // show.
                            let session = try await supabase.auth.session
                            guard !session.isExpired else {
                                authStatus = .signedOut
                                userSettings.reset()
                                continue
                            }

                            authStatus = .signedIn
                            Task { await userSettings.load() }
                        } catch {
                            authStatus = .signedOut
                            userSettings.reset()
                        }
                    case .signedOut:
                        authStatus = .signedOut
                        userSettings.reset()
                    default:
                        break
                    }
                }
            }
        }
    }

    init() {
        let postHogConfig = PostHogConfig(
            projectToken: "phc_CzRsJhyuTLxs9hDyknURWzxo8obRca4ytqeCjSssmWZk",
            host: "https://us.i.posthog.com"
        )
        PostHogSDK.shared.setup(postHogConfig)
        PostHogSDK.shared.captureLog(
            "iOS app started",
            level: .info,
            attributes: [
                "app.bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
                "app.version": Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "unknown",
            ]
        )

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
