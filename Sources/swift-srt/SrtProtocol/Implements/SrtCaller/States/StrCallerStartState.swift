//
//  StrCallerStartState.swift
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

struct StrCallerStartState: SrtCallerState {
    
    var name: SrtCallerStates = .start

    func auto(_ context: SrtCallerContext) {
        
        let inductionRequest = SrtHandshake.makeInductionRequest(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            serverIpAddress: context.peerIpAddress
        )

        /// An induction request is addressed to socket 0, which the listener reads as
        /// a connection request.
        let packet = SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: 0,
            contents: Data()
        )
        
        /// Advance before transmitting: the response can arrive the moment the
        /// request leaves, and it must find the context already expecting it.
        context.set(newState: .inductionRequesting)
        context.send(packet, inductionRequest.data)
        
    }
    
}
