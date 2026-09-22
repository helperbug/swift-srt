//
//  HandshakeExtensionFlagTypes.swift
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

enum HandshakeExtensionFlagTypes: UInt32, Sendable {
    case none = 0x00
    case handshakeRequest = 0x00000001
    case keyMaterialRequest = 0x00000002
    case configuration = 0x00000004

    var label: String {
        switch self {
        case .none:
            return "None"
        case .handshakeRequest:
            return "Handshake Request"
        case .keyMaterialRequest:
            return "Key Material Request"
        case .configuration:
            return "Configuration"
        }
    }
}
