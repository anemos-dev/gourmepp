//
//  Item.swift
//  ごはん日和
//
//  Created by 木村風葉 on 2026/07/17.
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
