//
//  ConnectionState.swift
//
//
//  Created by Ben Waidhofer on 4/30/24.
//

import Foundation
import Network

// MARK: Protocol

protocol ConnectionState {
    var name: ConnectionStates { get }
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State)
    func primary(_ context: ConnectionContext) -> Void
    func auto(_ context: ConnectionContext) -> Void
    func fail(_ context: ConnectionContext) -> Void
    func send(_ connection: NWConnection, _ data: Data) -> Void
}

extension ConnectionState {
    
    func primary(_ context: ConnectionContext) {
        fatalError(name.label)
    }

    func auto(_ context: ConnectionContext) {
        fatalError(name.label)
    }

    func fail(_ context: ConnectionContext) {
        fatalError(name.label)
    }
    
    func send(_ connection: NWConnection, _ data: Data) {
        fatalError(name.label)
    }
}


// MARK: Waiting State

class ConnectionWaitingState: ConnectionState {
    let name: ConnectionStates = .waiting
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
    }
    func primary(_ context: ConnectionContext) {}
    func auto(_ context: ConnectionContext) {}
    func fail(_ context: ConnectionContext) {}
}

// MARK: Preparing State

class ConnectionPreparingState: ConnectionState {
    let name: ConnectionStates = .preparing
    func onStateChanged(_ context: ConnectionContext,  state: NWConnection.State) {
        
    }
    func primary(_ context: ConnectionContext) {}
    func auto(_ context: ConnectionContext) {}
    func fail(_ context: ConnectionContext) {}
}


// MARK: Failed State

class ConnectionFailedState: ConnectionState {
    let name: ConnectionStates = .failed
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
    }
    func primary(_ context: ConnectionContext) {}
    func auto(_ context: ConnectionContext) {
        context.remove(context.key)
    }
    func fail(_ context: ConnectionContext) {}
}

// MARK: Cancelled State

class ConnectionCancelledState: ConnectionState {
    let name: ConnectionStates = .cancelled
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
    }
    func primary(_ context: ConnectionContext) {}
    func auto(_ context: ConnectionContext) {
        context.remove(context.key)
    }
    func fail(_ context: ConnectionContext) {}
}
