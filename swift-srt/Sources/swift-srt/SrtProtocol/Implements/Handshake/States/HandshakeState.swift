//
//  HandshakeState.swift
//
//
//  Created by Ben Waidhofer on 5/30/24.
//

import Foundation

protocol HandshakeState {
    
    var name: HandshakeStates { get }
    
    func onPacketReceived(_ context: HandshakeContext, packet: SrtPacket) -> Void
    func primary(_ context: HandshakeContext) -> Void
    func auto(_ context: HandshakeContext) -> Void
    func fail(_ context: HandshakeContext) -> Void
    
}

// MARK: Defaults

extension HandshakeState {
    
    func primary(_ context: HandshakeContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: HandshakeContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: HandshakeContext) {
        
        fatalError(name.label)
        
    }
    
    func onPacketReceived(_ context: HandshakeContext, packet: SrtPacket) {
        
        fatalError(name.label)

    }

}
