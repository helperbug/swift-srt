//
//  SrtListenerContext.swift
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

public class SrtListenerContext: SrtPacketSender {
    
    /// This listener's own socket ID, which it advertises to the caller.
    let srtSocketID: UInt32

    /// Socket ID of the caller, taken from the induction request. Every response
    /// is addressed to it.
    let peerSocketID: UInt32

    let initialPacketSequenceNumber: UInt32
    let synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool
    let send: (SrtPacket, Data) -> Void
    let onSocketCreated: (SrtSocketProtocol) -> Void

    /// The current handshake phase, observable so callers and tests can tell an
    /// established connection from one still negotiating.
    var state: SrtListenerStates { _state.name }

    private var _state: SrtListenerState
    
    init(
        srtSocketID: UInt32,
        peerSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        send: @escaping (SrtPacket, Data) -> Void,
        onSocketCreated: @escaping (SrtSocketProtocol) -> Void
    ) {
        self.srtSocketID = srtSocketID
        self.peerSocketID = peerSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self._state = StrListenerInducedState()
        self.send = send
        self.onSocketCreated = onSocketCreated
        
    }

    /// Sending from `init` meant the reply could arrive before the caller had a
    /// reference to hand it to. Starting is now a separate, explicit step.
    func start() {

        self._state.auto(self)

    }

    /// Parameters the caller asked for in its conclusion request.
    private(set) var streamId: String?
    private(set) var srtVersion: UInt32?
    private(set) var srtFlags: UInt32?
    private(set) var receiverTsbpdDelay: UInt16?
    private(set) var senderTsbpdDelay: UInt16?

    /// Record what the caller requested so the socket can be built from it.
    func apply(handshake: SrtHandshake) {

        self.streamId = handshake.streamId
        self.srtVersion = handshake.srtVersion
        self.srtFlags = handshake.srtFlags
        self.receiverTsbpdDelay = handshake.receiverTsbpdDelay
        self.senderTsbpdDelay = handshake.senderTsbpdDelay

    }

    func handleHandshake(handshake: SrtHandshake) {
        
        self._state.handleHandshake(self, handshake: handshake)
        
    }
    
    @discardableResult
    func set(newState: SrtListenerStates) -> SrtListenerState {
        
        print("setting listener state to \(newState.label)")
        self._state = newState.instance
        return self._state
        
    }
    
}
