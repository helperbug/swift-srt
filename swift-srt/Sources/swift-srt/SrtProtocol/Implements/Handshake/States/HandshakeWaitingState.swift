//
//  HandshakeWaitingState.swift
//
//
//  Created by Ben Waidhofer on 5/31/24.
//

import Foundation

struct HandshakeWaitingState: HandshakeState {
    
    let name: HandshakeStates = .waiting
    
    func onPacketReceived(_ context: HandshakeContext, packet: SrtPacket) {
        
        guard let handshake = SrtHandshake(data: packet.contents),
              handshake.isInductionRequest else {
            self.fail(context)
            return
        }

        self.auto(context)
        
    }
    
    func auto(_ context: HandshakeContext) {

        let state = context.set(newState: .responding)
        state.auto(context)

    }
    
    func fail(_ context: HandshakeContext) {

        context.set(newState: .error)

    }

}
