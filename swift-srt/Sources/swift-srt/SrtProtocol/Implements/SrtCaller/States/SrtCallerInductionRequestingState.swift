//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/15/24.
//

import Foundation

struct SrtCallerInductionRequestingState: SrtCallerState {
    var name: SrtCallerStates = .inductionRequesting

    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        if handshake.isInductionResponse {
            
            context.synCookie = handshake.synCookie
            
            let state = context.set(newState: .inducted)
            
            state.auto(context)
            
        } else {
            
            context.set(newState: .shutdown)
            
        }
        
    }
    
}
