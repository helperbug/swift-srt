//
//  SrtCallerState.swift
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

// MARK: Caller State Protocol

protocol SrtCallerState {
    
    var name: SrtCallerStates { get }
    
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) -> Void
    func primary(_ context: SrtCallerContext) -> Void
    func auto(_ context: SrtCallerContext) -> Void
    func fail(_ context: SrtCallerContext) -> Void
    
}

// MARK: Defaults

extension SrtCallerState {
    
    func primary(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    /// Handshakes arrive from the network, so an unexpected one in any state is
    /// a packet to drop -- never a reason to trap.
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {

        print("Ignoring \(handshake.handshakeType) handshake in caller state \(name.label)")

    }
    
}
