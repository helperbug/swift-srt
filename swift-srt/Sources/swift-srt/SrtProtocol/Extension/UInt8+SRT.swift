//
//  UInt8.swift
//
//
//  Created by Ben Waidhofer on 6/3/24.
//

import Foundation

extension UInt8 {
    /// A computed property to easily get bytes from UInt32 in big-endian form.
    var bytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian, Array.init)
    }
}
