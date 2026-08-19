//
//  Item.swift
//  North-Star Promise Meeting Assistant
//
//  Created by Dexter Jackson on 8/19/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
