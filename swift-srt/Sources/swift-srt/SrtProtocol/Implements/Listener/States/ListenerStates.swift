//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 4/30/24.
//

import Foundation

public enum ListenerStates {
    case none
    case ready
    case error
    
    var label: String {
        switch self {
        case .none:
            return "None"
        case .error:
            return "Error"
        case .ready:
            return "Ready"
        }
    }
}
