//
//  ListenerErrorState.swift
//  
//
//  Created by Ben Waidhofer on 5/29/24.
//

import Foundation
import Network

// MARK: Error State

struct ListenerErrorState: ListenerState {
    
    let name: ListenerStates = .error
    
    func auto(_ context: ListenerContext) {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            
            context.set(state: .none)
            
        }
        
    }
    
    func onStateChanged(_ context: ListenerContext, state: NWListener.State) { }
    
}
