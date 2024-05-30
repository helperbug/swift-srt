//
//  ListenerReadyState.swift
//
//
//  Created by Ben Waidhofer on 5/29/24.
//

import Foundation
import Network

// MARK: Ready State

struct ListenerReadyState: ListenerState {
    
    let name: ListenerStates = .ready
    
    func onStateChanged(_ context: ListenerContext, state: NWListener.State) {
        
        switch state {
            
        case .cancelled:
            
            context.set(state: .none)
            
        case .failed(_):
            
            context.set(state: .error)
            
        default:
            
            break
            
        }
        
    }
    
}
