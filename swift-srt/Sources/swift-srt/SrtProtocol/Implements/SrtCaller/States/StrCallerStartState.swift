//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/15/24.
//

import Foundation

struct StrCallerStartState: SrtCallerState {
    
    var name: SrtCallerStates = .start

    func auto(_ context: SrtCallerContext) {
        
        let inductionRequest = SrtHandshake.makeInductionRequest(serverIpAddress: context.peerIpAddress)
        
        let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data())
        let contents = inductionRequest.makePacket(socketId: 0).contents
        
        context.send(packet, inductionRequest.data)

        context.set(newState: .inductionRequesting)
        
    }
    
}
