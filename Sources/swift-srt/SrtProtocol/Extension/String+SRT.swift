//
//  String+SRT.swift
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

extension String {
    
    var ipStringToData: Data? {

        let components = self.split(separator: ".")
        guard components.count == 4 else { return nil }
        
        let ipv4Bytes = components.compactMap { UInt8($0) }.reversed()
        guard ipv4Bytes.count == 4 else { return nil }
        
        let paddedBytes = ipv4Bytes + [UInt8](repeating: 0, count: 12)
        return Data(paddedBytes)

    }
    
}
