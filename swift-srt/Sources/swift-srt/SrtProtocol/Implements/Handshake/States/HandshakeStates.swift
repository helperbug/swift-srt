//
//  HandshakeStates.swift
//
//
//  Created by Ben Waidhofer on 5/30/24.
//

import Foundation

public enum HandshakeStates {
    
    /// Waiting for an induction request
    case waiting
    /// Induction request received and response sent
    case responding
    /// Conclusion request received and response sent
    case concluding
    /// General error condition will send Shutdown and the SrtSocket will never form
    case error

    var instance: HandshakeState {
        
        switch self {

        case .waiting: return HandshakeWaitingState()

        case .responding: return HandshakeRespondingState()

        case .concluding: return HandshakeConcludingState()

        case .error: return HandshakeErrorState()

        }
        
    }

    var label: String {
        "\(self)"
    }
    
}
