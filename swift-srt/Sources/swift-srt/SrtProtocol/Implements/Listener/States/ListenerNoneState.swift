//
//  ListenerNoneState.swift
//  
//
//  Created by Ben Waidhofer on 5/29/24.
//

import Foundation
import Network

// MARK: None State

struct ListenerNoneState: ListenerState {
    let name: ListenerStates = .none
    
    func onStateChanged(_ context: ListenerContext, state: NWListener.State) {
        
        switch state {
            
        case .ready:
            
            context.set(state: .ready)
            
        case .failed(_):
            
            context.set(state: .error)
            
        default:
            
            break
            
        }
    }
    
    func auto(_ context: ListenerContext) {
        
        do {
            
            let listener = try NWListener(
                using: context.parameters,
                on: context.port
            )
            
            listener.newConnectionHandler = context.newConnectionHandler
            listener.stateUpdateHandler = context.onStateChanged(_ :)
            
            context.listener = listener
            listener.start(queue: .global(qos: .utility))
            listener.service = NWListener.Service(name: "SrtListener",
                                                  type: "_service._udp")
            
        } catch {
            
            context.set(state: .error)
            
        }
    }
}
