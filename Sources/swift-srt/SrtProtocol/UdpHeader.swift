//
//  UdpHeader.swift
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

import CryptoKit
import Foundation

public struct UdpHeader: Sendable {
    public let sourceIp: String
    public let sourcePort: UInt16
    public let destinationIp: String
    public let destinationPort: UInt16
    public let interface: String
    public let interfaceType: String

    var cookie: UInt32 {
        makeSynCookie()
    }
    
    private func makeSynCookie(mss: UInt8 = 5) -> UInt32 {
        
        let destinationIpBytes: [UInt8] = destinationIp.split(separator: ".").compactMap { UInt8($0) }
        let destinationPortByte: Data = withUnsafeBytes(of: destinationPort.bigEndian) { Data($0) }
        let sourceIpBytes: [UInt8] = sourceIp.split(separator: ".").compactMap { UInt8($0) }
        let sourcePortByte: Data = withUnsafeBytes(of: sourcePort.bigEndian) { Data($0) }
        let timestamp = UInt8((UInt32(Date().timeIntervalSince1970) / 64) % 32)
        
        var concatenatedData = Data()
        concatenatedData.append(contentsOf: destinationIpBytes)
        concatenatedData.append(destinationPortByte)
        concatenatedData.append(contentsOf: sourceIpBytes)
        concatenatedData.append(sourcePortByte)
        concatenatedData.append(timestamp)
        
        // Generate cryptographic hash (bottom 24 bits)
        let hash = SHA256.hash(data: concatenatedData)
        let hash24Bits = hash.prefix(3).reduce(0) { (result, byte) in (result << 8) | UInt32(byte) }
        
        // Combine timestamp, mss, and hash to form the SYN cookie
        let result = (UInt32(timestamp) << 27) | (UInt32(mss) << 24) | (hash24Bits & 0x00FFFFFF)
        
        //        print("MSS is \(mss)")
        //        print("Result (bits): \(binaryString)")
        //        let binaryString = String(result, radix: 2)
        
        return result
    }
    
    public static var blank: UdpHeader {
        .init(
            sourceIp: "-",
            sourcePort: 0,
            destinationIp: "-",
            destinationPort: 0,
            interface: "-",
            interfaceType: "-"
        )
    }
}

extension UdpHeader: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sourceIp)
        hasher.combine(sourcePort)
        hasher.combine(destinationIp)
        hasher.combine(destinationPort)
        hasher.combine(interface)
        hasher.combine(interfaceType)
    }
}
