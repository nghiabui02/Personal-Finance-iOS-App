//
//  Item.swift
//  Personal Finance
//
//  Created by Nghia Bui on 6/16/26.
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
