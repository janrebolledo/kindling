//
//  OnboardingView.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/24/26.
//
import SwiftUI

struct OnboardingView: View {
    @State private var step: Int = 1
    @State private var accessGranted = false
    

    var body: some View {
        if step == 1 {
            OnboardingStartView(step: $step)
        }
        if step == 2 {
            SignUpCaptureView()
        }
    }
}

#Preview {
    OnboardingView()
}
