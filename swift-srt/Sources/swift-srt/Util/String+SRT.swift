//
//  File.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
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
