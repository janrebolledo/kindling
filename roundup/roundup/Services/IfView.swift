//
//  IfView.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/16/26.
//

import SwiftUI


extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
