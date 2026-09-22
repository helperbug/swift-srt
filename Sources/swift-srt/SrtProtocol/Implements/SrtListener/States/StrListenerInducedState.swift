//
//  StrListenerInducedState.swift
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

struct StrListenerInducedState: SrtListenerState {
    
    let name: SrtListenerStates = .induced
    
    func auto(_ context: SrtListenerContext) {
        
        let inductionResponse = SrtHandshake.makeInductionResponse(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            synCookie: context.synCookie,
            peerIpAddress: context.peerIpAddress,
            encryptionField: context.passphrase == nil ? 0 : 2
        )

        /// The response is addressed to the caller's socket, while the handshake body
        /// advertises this listener's own socket ID.
        let packet = SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: context.peerSocketID,
            contents: Data()
        )

        /// Advance before transmitting: the conclusion request can arrive at once.
        context.set(newState: .inductionResponding)
        context.send(packet, inductionResponse.data)
        
    }

}
