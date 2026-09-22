//
//  SrtListenerState.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation
import Network

// MARK: Listener State Protocol

protocol SrtListenerState {
    
    var name: SrtListenerStates { get }
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) -> Void
    func primary(_ context: SrtListenerContext) -> Void
    func auto(_ context: SrtListenerContext) -> Void
    func fail(_ context: SrtListenerContext) -> Void
    
}

// MARK: Defaults

extension SrtListenerState {
    
    func primary(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    /// Handshakes arrive from the network, so an unexpected one in any state is
    /// a packet to drop -- never a reason to trap.
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {

        print("Ignoring \(handshake.handshakeType) handshake in listener state \(name.label)")

    }
    
}
