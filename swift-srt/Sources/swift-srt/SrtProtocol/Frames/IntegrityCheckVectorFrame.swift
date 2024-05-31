//
//  IntegrityCheckVectorFrame.swift
//  
//
//  Created by Ben Waidhofer on 5/31/24.
//

import Foundation

struct IntegrityCheckVectorFrame {
    let icv: Data
    let evenSEK: Data
    let oddSEK: Data

    var data: Data {
        icv + evenSEK + oddSEK
    }

    static func makeWrapper() -> IntegrityCheckVectorFrame {
        .init(
            icv: .random(8),
            evenSEK: .random(32),
            oddSEK: .random(32)
        )
    }
}
