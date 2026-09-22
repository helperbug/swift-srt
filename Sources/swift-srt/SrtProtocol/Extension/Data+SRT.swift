//
//  Data+SRT.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation

extension Data {
    
    var asHexArray: String {
        var rows: [String] = []
        var counter = 0
        var row = ""
        
        for value in self {
            row += String(format: "%02X", value) + " "
            counter += 1
            
            if counter == 4 {
                row += " "
            }
            
            if counter == 8 {
                counter = 0
                rows.append(row)
                row = ""
            }
        }
        
        return rows.joined(separator: "\n")
    }
    
    var asString: String? {
        if let string = String(data: self, encoding: .utf8) {
            return string.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }
    
    func toUInt32(from offset: inout Int) -> UInt32 {
        let size = MemoryLayout<UInt32>.size
        defer { offset += size }
        return self.subdata(in: offset..<(offset + size)).reversed().withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    func toUInt16(from offset: inout Int) -> UInt16 {
        let size = MemoryLayout<UInt16>.size
        defer { offset += size }
        return self.subdata(in: offset..<(offset + size)).reversed().withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    subscript(range: Range<Int>) -> Data {
        return self.subdata(in: range)
    }
    
    static func random(_ length: Int) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: 0...255) })
    }
    
}
