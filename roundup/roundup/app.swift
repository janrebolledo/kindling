//
//  roundupApp.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import Supabase
import SwiftUI

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
            .task {
                for await state in supabase.auth.authStateChanges {
                    if [.initialSession, .signedIn, .signedOut].contains(
                        state.event
                    ) {
                        authenticated = state.session != nil
                    }
                }
            }
        }

    }
}
