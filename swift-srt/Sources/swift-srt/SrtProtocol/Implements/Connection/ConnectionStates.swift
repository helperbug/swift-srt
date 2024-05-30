//
//  ConnectionStates.swift
//
//
//  Created by Ben Waidhofer on 4/30/24.
//

import SwiftUI

public enum ConnectionStates {
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
}
