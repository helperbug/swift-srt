//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/1/24.
//

import Foundation

public enum HandshakeExtensionTypes: UInt16 {
    case none
    case handshakeRequest = 1
    case handshakeResponse = 2
    case keyMaterialRequest = 3
    case keyMaterialResponse = 4
    case streamId = 5
    case congestionControl = 6
    case filterControl = 7
    case groupControl = 8

    var label: String {
        switch self {
        case .none:
            return "None"
        case .handshakeRequest:
            return "Handshake Request"
        case .handshakeResponse:
            return "Handshake Response"
        case .keyMaterialRequest:
            return "Key Material Request"
        case .keyMaterialResponse:
            return "Key Material Response"
        case .streamId:
            return "Stream ID"
        case .congestionControl:
            return "Congestion Control"
        case .filterControl:
            return "Filter Control"
        case .groupControl:	
            return "Group Control"
        }
    }

    var abbreviation: String {
        switch self {
        case .none:
            return "NONE"
        case .handshakeRequest:
            return "SRT_CMD_HSREQ"
        case .handshakeResponse:
            return "SRT_CMD_HSRSP"
        case .keyMaterialRequest:
            return "SRT_CMD_KMREQ"
        case .keyMaterialResponse:
            return "SRT_CMD_KMRSP"
        case .streamId:
            return "SRT_CMD_SID"
        case .congestionControl:
            return "SRT_CMD_CONGESTION"
        case .filterControl:
            return "SRT_CMD_FILTER"
        case .groupControl:
            return "SRT_CMD_GROUP"
        }
    }
}
