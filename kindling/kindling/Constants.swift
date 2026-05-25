//
//  Constants.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import SwiftUI

enum AnimationConstants {
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7)
    static let springFast = Animation.spring(response: 0.25, dampingFraction: 0.8)
}

enum LayoutConstants {
    static let heroHeight: CGFloat = 500
}
