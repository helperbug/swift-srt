//
//  HandshakeRespondingState.swift
//
//
//  Created by Ben Waidhofer on 5/31/24.
//

import Foundation

struct HandshakeRespondingState: HandshakeState {
    
    let name: HandshakeStates = .responding

    func auto(context: HandshakeContext) {
        
        let response = SrtHandshake.makeInductionResponse(srtSocketID: context.socketId,
                                                          initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                                                          synCookie: context.synCookie,
                                                          peerIpAddress: context.peerIpAddress,
                                                          encrypted: false)
        
    }
    
}
