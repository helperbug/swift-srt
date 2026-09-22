//
//  SrtCallerActiveState.swift
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

struct SrtCallerActiveState: SrtCallerState {
    var name: SrtCallerStates = .active

    func auto(_ context: SrtCallerContext) {

        /// The listener has answered, so the connection is established. The socket is
        /// keyed by this caller's own ID, which is the destination the listener puts
        /// on the packets it sends back.
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

        /// Carry across what the listener agreed to in its conclusion response.
        socket.srtVersion = context.srtVersion
        socket.srtFlags = context.srtFlags
        socket.receiverTsbpdDelay = context.receiverTsbpdDelay
        socket.senderTsbpdDelay = context.senderTsbpdDelay
        socket.streamId = context.streamId

        context.socketCreated(socket)

    }

    /// A repeated conclusion response means our answer was lost; it is safely ignored
    /// because the connection is already up.
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) { }

}
