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
        
        if state == .preparing {
            
            let state = context.set(newState: .setup)
            state.state.auto(context)

        } else if state == .ready {
            
            let state = context.set(newState: .ready)
            state.state.auto(context)

        }
        
        if let queue = context.connection.queue {
            context.connection.requestEstablishmentReport(queue: queue) { report in
                guard let report else {
                    return
                }
                
                print(String(format: "Duration of establishment: %.0f microseconds", report.duration * 1000000))
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

    }
    
    func fail(_ context: ConnectionContext) {

        context.connection.cancel()

    }
    
}
