//
//  Jiggle.swift
//  roundup
//
//  Created by Jan Rebolledo on 1/25/26.
//

import SwiftUI

extension View {
    func jiggle(amount: Double = 2.0, duration: Double = 0.15) -> some View {
        modifier(JiggleViewModifier(amount: amount, duration: duration))
    }
}

private struct JiggleViewModifier: ViewModifier {
    let amount: Double
    let duration: Double
    @State private var isJiggling = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isJiggling ? amount : -amount), anchor: .center)
            .animation(
                Animation.easeInOut(duration: duration)
                    .repeatForever(autoreverses: true),
                value: isJiggling
            )
            .onAppear {
                isJiggling.toggle()
            }
    }
}
