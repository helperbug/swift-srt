//
//  ListenerState.swift
//
//
//  Created by Ben Waidhofer on 4/30/24.
//

import Foundation
import Network

// MARK: Listener State Protocol

protocol ListenerState {
    
    var name: ListenerStates { get }
    
    func onStateChanged(_ context: ListenerContext, state: NWListener.State) -> Void
    func primary(_ context: ListenerContext) -> Void
    func auto(_ context: ListenerContext) -> Void
    func fail(_ context: ListenerContext) -> Void
    
}

// MARK: Defaults

extension ListenerState {
    
    func primary(_ context: ListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: ListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: ListenerContext) {
        
        fatalError(name.label)
        
    }
    
}

