//
//  StrListenerInductedState.swift
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

struct StrListenerInductedState: SrtListenerState {
    
    let name: SrtListenerStates = .inducted
    
    func auto(_ context: SrtListenerContext) {
        
        /// Echo the key material we accepted, or the four-byte reason we did not.
        let keyMaterialResponse: Data?
        if let encryption = context.encryption {
            keyMaterialResponse = encryption.keyMaterial
        } else if let error = context.encryptionError {
            keyMaterialResponse = SrtEncryption.refusal(error)
        } else {
            keyMaterialResponse = nil
        }

        let conclusionResponse = SrtHandshake.makeConclusionResponse(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            synCookie: context.synCookie,
            peerIpAddress: context.peerIpAddress,
            keyMaterialResponse: keyMaterialResponse,
            encryptionField: context.encryption?.encryptionField ?? (context.passphrase == nil ? 0 : 2)
        )

        /// Addressed to the caller, advertising this listener's own socket ID.
        let packet = SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: context.peerSocketID,
            contents: Data()
        )

        /// A refused exchange still gets its answer, but no socket.
        if context.encryptionError != nil {
            context.set(newState: .shutdown)
            context.send(packet, conclusionResponse.data)
            return
        }

        /// The socket is keyed by this listener's own ID: that is what the caller
        /// puts in the destination field of everything it sends. Register it, and
        /// move to active, before the response goes out -- the caller may send data
        /// the instant it lands.
        let socket = SrtSocketContext(
            encrypted: context.encrypted,
            socketId: context.srtSocketID,
            peerSocketId: context.peerSocketID,
            synCookie: context.synCookie
        )

        /// The receive buffer starts where the peer said its first data packet
        /// will; our first data packet starts where we told the peer.
        socket.initialPacketSequenceNumber = context.peerInitialSequence ?? context.initialPacketSequenceNumber
        socket.ownInitialSequenceNumber = context.initialPacketSequenceNumber
        socket.encryption = context.encryption

        /// Carry across what the caller asked for in its conclusion request.
        socket.srtVersion = context.srtVersion
        socket.srtFlags = context.srtFlags
        socket.receiverTsbpdDelay = context.receiverTsbpdDelay
        socket.senderTsbpdDelay = context.senderTsbpdDelay
        socket.streamId = context.streamId

        context.set(newState: .active)
        context.socketCreated(socket)
        context.send(packet, conclusionResponse.data)
        
    }

}
