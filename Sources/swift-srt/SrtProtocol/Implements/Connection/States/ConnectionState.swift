//
//  ConnectionState.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  Portions of this project are based on the SRT protocol specification.
//  SRT is licensed under the Mozilla Public License, v. 2.0.
//  You may obtain a copy of the License at
//  https://github.com/Haivision/srt/blob/master/LICENSE
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Network

// MARK: Protocol

/// States run with the connection's lock held and mutate its confined state
/// through the inout parameter. They may call the connection's lock-free
/// methods (`send`, `cancel`, `receiveNextMessage`, `log`) and nothing else.
///
/// A state that completes a handshake returns the new socket, and the caller
/// hands it to the subscriber after the lock is released.
protocol ConnectionState {
    var name: ConnectionStates { get }
    func onStateChanged(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext, state: NWConnection.State) -> SrtSocket?
    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket?
}

extension ConnectionState {

    /// Network events arriving in a state that has no use for them are dropped,
    /// never trapped on.
    func onStateChanged(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext, state: NWConnection.State) -> SrtSocket? {
        context.log("Ignoring \(state) in connection state \(name.label)")
        return nil
    }

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? { nil }
}

// MARK: Waiting State

struct ConnectionWaitingState: ConnectionState {
    let name: ConnectionStates = .waiting
}

// MARK: Preparing State

struct ConnectionPreparingState: ConnectionState {
    let name: ConnectionStates = .preparing
}

// MARK: Failed State

struct ConnectionFailedState: ConnectionState {
    let name: ConnectionStates = .failed

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? {
        context.cancel()
        context.notifyClosed(&confined)
        return nil
    }
}

// MARK: Cancelled State

struct ConnectionCancelledState: ConnectionState {
    let name: ConnectionStates = .cancelled

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? {
        context.notifyClosed(&confined)
        return nil
    }
}
