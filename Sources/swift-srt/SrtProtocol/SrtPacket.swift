//
//  SrtPacket.swift
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

public struct SrtPacket: Sendable {
    
    let data: Data
    
    var isData: Bool {
        
        guard data.count > 0 else {
            return false
        }
        
        return (data[0] & 0b10000000) == 0
        
    }
    
    var field1: UInt32 {
        
        guard data.count > 15 else {
            return 0
        }
        
        return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0x7FFFFFFF

    }
    
    var field2: UInt32 {

        guard data.count > 15 else {
            return 0
        }
        
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
    
    var timestamp: UInt32 {

        guard data.count > 15 else {
            return 0
        }

        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    var destinationSocketID: UInt32 {

        guard data.count > 15 else {
            return 0
        }

        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    var contents: Data {

        guard data.count > 15 else {
            return Data()
        }

        return data.subdata(in: 16..<data.count)

    }
    
    init(isData: Bool = false, field1: UInt32, field2: UInt32 = 0, timestamp: UInt32 = UInt32(Date().timeIntervalSince1970), socketID: UInt32, contents: Data) {
        
        var data = Data(capacity: 16 + contents.count)
        
        let field1WithIsData = (field1 & 0x7FFFFFFF) | (isData ? 0x00000000 : 0x80000000)
        var field1BigEndian = field1WithIsData.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &field1BigEndian) { Data($0) })

        var field2BigEndian = field2.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &field2BigEndian) { Data($0) })
        
        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })
        
        var socketIdBigEndian = socketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &socketIdBigEndian) { Data($0) })

        data.append(contents)
        
        self.data = data
    }
    
    init(data: Data) {
        self.data = data
    }

    /// The same packet with its timestamp field rewritten. Packets are built
    /// where the protocol logic lives and stamped where they hit the wire.
    func stamped(_ timestamp: UInt32) -> SrtPacket {
        guard data.count >= 16 else { return self }
        var copy = data
        var bigEndian = timestamp.bigEndian
        withUnsafeBytes(of: &bigEndian) { copy.replaceSubrange(8..<12, with: $0) }
        return SrtPacket(data: copy)
    }
    
    public static var blank: SrtPacket {
        SrtPacket(
            isData: false,
            field1: 0,
            field2: 0,
            socketID: 0,
            contents: Data()
        )
    }
}
