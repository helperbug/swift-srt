//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/15/24.
//

import Foundation

struct SrtCallerConclusionRequestingState: SrtCallerState {
    var name: SrtCallerStates = .conclusionRequesting

    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        if handshake.isConclusionRequest(synCookie: context.synCookie) {
            
            let state = context.set(newState: .active)
            
            state.auto(context)
            
        } else {
            
            context.set(newState: .shutdown)
            
        }
        
    }
}
