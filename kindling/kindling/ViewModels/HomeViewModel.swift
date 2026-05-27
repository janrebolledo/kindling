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
    var searchQuery: String = ""
    var isSearching: Bool = false

    init() {
    }

    deinit {
    }
}
