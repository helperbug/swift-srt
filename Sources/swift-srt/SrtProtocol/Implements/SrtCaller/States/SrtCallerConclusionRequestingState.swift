//
//  SrtCallerConclusionRequestingState.swift
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

struct SrtCallerConclusionRequestingState: SrtCallerState {
    var name: SrtCallerStates = .conclusionRequesting

    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        /// The listener replies with a conclusion response carrying HSRSP -- not with
        /// another conclusion request.
        guard handshake.isConclusionResponse else {

            print("Caller: not a conclusion response (type \(handshake.handshakeType), ext 0x\(String(handshake.extensionField, radix: 16)), exts \(handshake.extensions.keys.map(\.label))); giving up")
            context.set(newState: .shutdown)
            return

        }

        guard handshake.hasUsableTransmissionParameters else {

            print("Rejecting conclusion response with unusable transmission parameters")
            context.set(newState: .shutdown)
            return

        }

        context.apply(handshake: handshake)

        /// Our key material must come back verbatim; four bytes is a refusal.
        if let encryption = context.encryption {
            guard let response = handshake.keyMaterialResponse else {
                print("Caller: peer answered without key material; refusing to run in the clear")
                context.fail(encryption: .peerRejected(.unsecured))
                context.set(newState: .shutdown)
                return
            }
            if case .failure(let error) = encryption.accept(keyMaterialResponse: response) {
                print("Caller: key exchange failed: \(error)")
                context.fail(encryption: error)
                context.set(newState: .shutdown)
                return
            }
        }

        /// The peer's socket only exists once it accepts, so this response is
        /// the first packet that can carry its real ID. libsrt's induction
        /// response echoes the caller's own ID there, so trusting that would
        /// address every reply to ourselves.
        context.peerSocketID = handshake.srtSocketID

        let state = context.set(newState: .active)
        state.auto(context)
        
    }
}
