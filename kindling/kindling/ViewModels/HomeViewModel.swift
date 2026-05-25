//
//  HomeViewModel.swift
//  roundup
//
//  Created by Jan Rebolledo on 2/24/26.
//

import Observation
import SwiftUI
import UIKit

@Observable
class HomeViewModel {
    var selectedTab: tab? = .new
    var animatedTab: tab? = .new
    var searchQuery: String = ""
    var isSearching: Bool = false
    var keyboardHeight: CGFloat = 0

    private var keyboardShowObserver: Any?
    private var keyboardHideObserver: Any?

    init() {
        keyboardShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                let frame = notification.userInfo?[
                    UIResponder.keyboardFrameEndUserInfoKey
                ] as? CGRect
            else { return }
            withAnimation(AnimationConstants.spring) {
                self.keyboardHeight = frame.height
            }
        }

        keyboardHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            withAnimation(AnimationConstants.spring) {
                self.keyboardHeight = 0
            }
        }
    }

    deinit {
        if let observer = keyboardShowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = keyboardHideObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func switchTab(_ newTab: tab?) {
        withAnimation(AnimationConstants.spring) {
            animatedTab = newTab
        }
    }
}
