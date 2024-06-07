//
//  SrtListenerInductionRespondingState.swift
//  
//
//  Created by Ben Waidhofer on 6/7/24.
//

import Foundation

struct SrtListenerInductionRespondingState: SrtListenerState {
    
    let name: SrtListenerStates = .inductionResponding
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {
        
        if handshake.isConclusionRequest(synCookie: context.synCookie) {
            
            let state = context.set(newState: .inducted)
            state.auto(context)
            
        } else {
            
            context.set(newState: .shutdown)
            
        }
        
    }
    
}
