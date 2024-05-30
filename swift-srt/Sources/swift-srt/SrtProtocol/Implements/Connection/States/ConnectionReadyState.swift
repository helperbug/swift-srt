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
        
    }

    func primary(_ context: ConnectionContext) {
        
    }

    func auto(_ context: ConnectionContext) { }
    func fail(_ context: ConnectionContext) { }
    
    // Receive a message, deliver it to your delegate, and continue receiving more messages.
    func receiveNextMessage(_ context2: ConnectionContext) {
        context2.connection.receiveMessage { (content, context, isComplete, error) in
            /// first check for errors
            if let error = error {
                /// deal with error
                print(error)
                return
            }
            
            /// make sure there is a context
            guard let context = context else {
                /// bad, probably an error
                print("no context")
                return
            }
            
            /// get the protocol metadata for the llrp protocol framer
            guard let protocolMetadata = context.protocolMetadata(definition: SrtProtocolFramer.definition) else {
                /// this should never happen
                print("protocol metadata is not present")
                return
            }
            
            // make sure the incoming message can be framed llrp
            guard protocolMetadata is NWProtocolFramer.Message else {
                print("network protocol framer could not downcast srt message")
                return
            }
            
            /// make sure there is data
            guard content != nil else {
                print("no data for message") // \(llrpMessage.messageType) id \(llrpMessage.messageId)")
                // Continue to receive more messages until an error is received
                self.receiveNextMessage(context2)
                return
            }
            
            print("routing message") // \(llrpMessage.messageType) \(llrpMessage.llrpHeader.messageId) count \(data.count)")
            
            // print(srtMessage.srtHeader, data)
            
            // Continue to receive more messages until an error is received
            self.receiveNextMessage(context2)
        }
    }
}
