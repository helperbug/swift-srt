//
//  UdpHeader.swift
//
//
//  Created by Ben Waidhofer on 5/8/24.
//

import CryptoKit
import Foundation

public struct UdpHeader {
    let sourceIp: String
    let sourcePort: UInt16
    let destinationIp: String
    let destinationPort: UInt16
    
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
}
