//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/1/24.
//

import Foundation

public enum HandshakeExtensionTypes: UInt16 {
    case none = 0
    case handshakeRequest = 1
    case handshakeResponse = 2
    case keyMaterialRequest = 3
    case keyMaterialResponse = 4
    case sessionId = 5
    case congestionControl = 6
    case filterControl = 7
    case groupControl = 8
}
