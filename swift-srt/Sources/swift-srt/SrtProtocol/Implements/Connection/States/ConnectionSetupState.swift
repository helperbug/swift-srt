//
//  ConnectionSetupState.swift
//
//
//  Created by Ben Waidhofer on 5/27/24.
//

import Foundation
import Network

class ConnectionSetupState: ConnectionState {
    
    let name: ConnectionStates = .setup
    
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        if case .ready = state {
            
        }
        
        if let queue = context.connection.queue {
            context.connection.requestEstablishmentReport(queue: queue) { report in
                guard let report else {
                    return
                }
                
                print("Duration of establishment: \(report.duration) seconds")
                //                print("Attempt started after: \(report.attemptStartedAfterInterval) seconds")
                //                print("Previous attempts: \(report.previousAttemptCount)")
                //                print("Used proxy: \(report.usedProxy)")
                //                print("Proxy configured: \(report.proxyConfigured)")
                //                if let proxy = report.proxyEndpoint {
                //                    print("Proxy endpoint: \(proxy)")
                //                }
            }
        }
    }
    
    func auto(_ context: ConnectionContext) {
        
        context.connection.start(queue: .global(qos: .utility))
        receiveNextMessage(context)
    }
    
    func fail(_ context: ConnectionContext) {
        context.connection.cancel()
        //        context.state = ConnectionErr
    }
    
    func receiveMessage(completion: @escaping @Sendable (_ content: Data?, _ contentContext: NWConnection.ContentContext?, _ isComplete: Bool, _ error: NWError?) -> Void) {
        
    }
    
    func receiveNextMessage(_ connectionContext: ConnectionContext) {
        connectionContext.connection.receiveMessage { (content, context, isComplete, error) in
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
            guard let srtMessage = protocolMetadata as? NWProtocolFramer.Message else {
                print("network protocol framer could not downcast SRT message")
                return
            }
            
            /// make sure there is data
            guard let data = content else {
                print("no data for message")
                // Continue to receive more messages until an error is received
                self.receiveNextMessage(connectionContext)
                return
            }
            
            print("routing message count \(data.count)")
            var counter = 0
            
            for value in data {
                print(String(format: "%02X", value), terminator: " ") // Prints each value in hexadecimal format
                counter += 1
                
                if counter == 8 {
                    print() // Print a newline character after printing 8 values
                    counter = 0 // Reset the counter for the next line
                }
            }

//            if let handshake = SrtHandshake(data: data) {
//                print(handshake)
//                let response = SrtHandshake.makeInductionResponse(srtSocketID: handshake.srtSocketID, host: context2.host, port: context2.portNumber)
//                print(response)
//                print(response.data.asHexArray)
//                self.send(context2.connection, response.data)
//            } else {
//                print(String(data: data, encoding: .utf8) ?? "")
//            }
            
            // self.receivePublisher.send((llrpMessage.llrpHeader, data))
            
            // Continue to receive more messages until an error is received
            let header = srtMessage.srtPacket
            print(header ?? "")
            
            self.receiveNextMessage(connectionContext)
        }
    }
    
    func send(_ connection: NWConnection, _ data: Data) {

//        let header = SrtPacketHeader(isControl: true, data: data)
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
