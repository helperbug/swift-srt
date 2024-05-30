//
//  ConnectionReadyState.swift
//
//
//  Created by Ben Waidhofer on 5/27/24.
//

import Foundation
import Network

class ConnectionReadyState: ConnectionState {
    
    let name: ConnectionStates = .ready
    
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
        switch state {
            
        case .failed(let error):
            print("Connection failed with error: \(error)")
            context.set(newState: .failed).state.auto(context)
            
        case .cancelled:
            print("Connection is cancelled.")
            context.set(newState: .cancelled).state.auto(context)
            
        default:
            print("Unexpected change while in ready state: \(state)")
        }
        
    }
    
    func auto(_ context: ConnectionContext) {
        
        context.receiveNextMessage()
        
    }
    
    func send(_ connection: NWConnection, _ data: Data) {
        
        let srtPacket = SrtPacket(data: data)
        
        // Create the framer message
        let message = NWProtocolFramer.Message(srtPacket: srtPacket)
        let metadata = [message]
        let identifier = "\(self)"
        
        // Create the content context
        let context = NWConnection.ContentContext(identifier: identifier, metadata: metadata)
        
        // Send the message data
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
    
}
