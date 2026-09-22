//
//  ConnectionStates.swift
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

import SwiftUI

public enum ConnectionStates: Sendable {
    case setup
    case waiting
    case preparing
    case ready
    case failed
    case cancelled

    public var label: String {
        switch self {
        case .setup:
            return "Setup"
        case .waiting:
            return "Waiting"
        case .preparing:
            return "Preparing"
        case .ready:
            return "Ready"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    public var color: Color {
        switch self {
        case .setup:
            return Color.gray
        case .waiting:
            return Color.orange
        case .preparing:
            return Color.blue
        case .ready:
            return Color.green
        case .failed:
            return Color.red
        case .cancelled:
            return Color.purple
        }
    }

    public var symbol: String {
        switch self {
        case .setup:
            return "gear"
        case .waiting:
            return "hourglass"
        case .preparing:
            return "hammer.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "multiply.circle.fill"
        }
    }
    
    var state: ConnectionState {
        
        switch self {
        case .setup:
            return ConnectionSetupState()
        case .waiting:
            return ConnectionWaitingState()
        case .preparing:
            return ConnectionPreparingState()
        case .ready:
            return ConnectionReadyState()
        case .failed:
            return ConnectionFailedState()
        case .cancelled:
            return ConnectionCancelledState()
        }
        
    }
}
