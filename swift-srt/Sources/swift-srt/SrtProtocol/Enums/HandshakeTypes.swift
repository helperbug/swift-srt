//
//  HandshakeTypes.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
//

import Foundation

/// Enumerates the possible types of handshakes in the SRT protocol.
public enum HandshakeTypes: UInt32, CaseIterable {
    case done = 0xFFFFFFFD
    case agreement = 0xFFFFFFFE
    case conclusion = 0xFFFFFFFF
    case waveAHand = 0x00000000
    case induction = 0x00000001
}
