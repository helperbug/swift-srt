//
//  ListenerReadyState.swift
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
import Network

// MARK: Ready State

struct SrtPortListenerReadyState: SrtPortListenerState {

    let name: SrtPortListnerStates = .ready

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State) {

        switch state {
        case .cancelled:
            context.transition(&confined, to: .none)
        case .failed(let error):
            context.log("Listener failed: \(error)")
            context.transition(&confined, to: .error)
        default:
            break
        }
    }
}
