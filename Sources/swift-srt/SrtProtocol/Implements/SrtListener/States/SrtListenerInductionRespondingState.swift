//
//  SrtListenerInductionRespondingState.swift
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

struct SrtListenerInductionRespondingState: SrtListenerState {
    
    let name: SrtListenerStates = .inductionResponding
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {

        /// A repeated induction request means our response was lost in flight.
        if handshake.isInductionRequest {

            context.set(newState: .induced).auto(context)
            return

        }

        guard handshake.isConclusionRequest(synCookie: context.synCookie) else {

            /// A mismatched cookie is a forged or stale packet. Drop it and stay
            /// put; tearing the listener down here would let any peer cancel a
            /// handshake in progress.
            print("Ignoring conclusion request with an unrecognised cookie")
            return

        }

        guard handshake.hasUsableTransmissionParameters else {

            print("Ignoring conclusion request with unusable transmission parameters")
            return

        }

        context.apply(handshake: handshake)

        /// Key exchange. A caller that offers keys gets them back if our
        /// passphrase unwraps them; one that offers none while we require them
        /// is refused, as libsrt's enforced encryption does.
        if let request = handshake.keyMaterialRequest {
            switch SrtEncryption.respond(toKeyMaterial: request, passphrase: context.passphrase) {
            case .success(let encryption):
                context.install(encryption: encryption)
            case .failure(let error):
                print("Listener: key exchange failed: \(error)")
                context.fail(encryption: error)
                context.set(newState: .inducted).auto(context)   // answers with the refusal, then stops
                return
            }
        } else if context.passphrase != nil {
            print("Listener: caller offered no key material; refusing to run in the clear")
            context.fail(encryption: .noSecret)
            context.set(newState: .shutdown)
            return
        }

        context.set(newState: .inducted).auto(context)
        
    }
    
}
