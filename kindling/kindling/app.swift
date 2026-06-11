//
//  roundupApp.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

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

    var body: some Scene {

        WindowGroup {
            Group {
                if !authenticated {
                    OnboardingView()
                } else {
                    ContentView()
                }
            }
            .environment(\.isAuthenticated, authenticated)
            .task {
                for await state in supabase.auth.authStateChanges {
                    if [.initialSession, .signedIn, .signedOut].contains(
                        state.event
                    ) {
                        if let session = state.session {
                            authenticated = !session.isExpired
                        } else {
                            authenticated = false
                        }
                    }
                }
            }
        }
    }
}
