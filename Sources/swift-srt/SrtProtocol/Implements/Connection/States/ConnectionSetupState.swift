//
//  ConnectionSetupState.swift
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

struct ConnectionSetupState: ConnectionState {

    let name: ConnectionStates = .setup

    func onStateChanged(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext, state: NWConnection.State) -> SrtSocket? {

        switch state {
        case .preparing:
            /// Already started; calling start() again on a live NWConnection traps.
            context.log("Connection preparing")
            return nil

        case .ready:
            return confined.set(.ready).auto(&confined, context)

        case .failed(let error):
            context.log("Connection failed during setup: \(error)")
            return confined.set(.failed).auto(&confined, context)

        case .cancelled:
            return confined.set(.cancelled).auto(&confined, context)

        default:
            return nil
        }
    }

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? {
        context.connection.start(queue: context.queue)
        return nil
    }
}
