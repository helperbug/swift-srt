//
//  HandshakeExtensionFlagTypes.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
//

import Foundation

enum HandshakeExtensionFlagTypes: UInt32 {
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
