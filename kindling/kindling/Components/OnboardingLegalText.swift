//
//  OnboardingLegalText.swift
//  kindling
//

import SwiftUI

enum KindlingLegal {
    static let termsURL = URL(string: "https://getkindl.ing/terms")!
    static let privacyURL = URL(string: "https://getkindl.ing/privacy")!
}

struct OnboardingLegalText: View {
    var body: some View {
        Text(attributed)
            .font(.system(size: 12))
            .foregroundStyle(kindlingMuted)
            .multilineTextAlignment(.center)
            .tracking(-0.12)
            .tint(kindlingMuted)
    }

    private var attributed: AttributedString {
        var text = AttributedString(
            "By continuing, you agree to kindling's Terms & Conditions and acknowledge the Privacy Policy."
        )
        let muted = kindlingMuted
        if let range = text.range(of: "Terms & Conditions") {
            text[range].link = KindlingLegal.termsURL
            text[range].underlineStyle = .single
            text[range].foregroundColor = muted
        }
        if let range = text.range(of: "Privacy Policy") {
            text[range].link = KindlingLegal.privacyURL
            text[range].underlineStyle = .single
            text[range].foregroundColor = muted
        }
        return text
    }
}
