//
//  ListenerState.swift
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

// MARK: Listener State Protocol

/// States run with the listener's lock held and mutate its confined state
/// through the inout parameter.
protocol SrtPortListenerState {

    var name: SrtPortListnerStates { get }

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State)
    func auto(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext)

}

// MARK: Defaults

extension SrtPortListenerState {

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State) {
        context.log("Ignoring \(state) in listener state \(name.label)")
    }

    func auto(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext) { }

}
