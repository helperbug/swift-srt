//
//  FixedWidthInteger+SRT.swift
//  
//
//  Created by Ben Waidhofer on 6/4/24.
//

import Foundation

extension FixedWidthInteger {
    var bytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }
}
