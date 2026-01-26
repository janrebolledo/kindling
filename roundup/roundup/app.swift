//
//  roundupApp.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/14/26.
//

import SwiftUI

@main
struct AppEntry: App {
    @State private var onboardingCompleted = false
    @State private var authenticated = false

    var body: some Scene {
        WindowGroup {
            if !onboardingCompleted {
                OnboardingView()
            } else {
                ContentView()
            }
        }
    }
}
