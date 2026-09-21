//
//  SrtCallerContext
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

public class SrtCallerContext: SrtPacketSender {
    
    let srtSocketID: UInt32

    /// Socket ID of the listener, learned from the induction response. Every packet
    /// after induction is addressed to it.
    var peerSocketID: UInt32 = 0

    let initialPacketSequenceNumber: UInt32
    var synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool

    /// Path the caller asks the listener for, sent as SRT_CMD_SID.
    let streamId: String?

    let send: (SrtPacket, Data) -> Void
    let onSocketCreated: (SrtSocketProtocol) -> Void

    /// Parameters the listener agreed to in its conclusion response.
    private(set) var srtVersion: UInt32?
    private(set) var srtFlags: UInt32?
    private(set) var receiverTsbpdDelay: UInt16?
    private(set) var senderTsbpdDelay: UInt16?

    /// The current handshake phase, observable so callers and tests can tell an
    /// established connection from one still negotiating.
    var state: SrtCallerStates { _state.name }

    private var _state: SrtCallerState
    
    init(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        streamId: String? = nil,
        send: @escaping (SrtPacket, Data) -> Void,
        onSocketCreated: @escaping (SrtSocketProtocol) -> Void
    ) {

        self.srtSocketID = srtSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self.streamId = streamId
        self._state = StrCallerStartState()
        self.send = send
        self.onSocketCreated = onSocketCreated
        
    }

    /// Sending from `init` meant the reply could arrive before the caller had a
    /// reference to hand it to. Starting is now a separate, explicit step.
    func start() {

        self._state.auto(self)

    }

    func handleHandshake(handshake: SrtHandshake) {
        
        self._state.handleHandshake(self, handshake: handshake)
        
    }

    /// Record what the listener agreed to so the socket can be built from it.
    func apply(handshake: SrtHandshake) {

        self.srtVersion = handshake.srtVersion
        self.srtFlags = handshake.srtFlags
        self.receiverTsbpdDelay = handshake.receiverTsbpdDelay
        self.senderTsbpdDelay = handshake.senderTsbpdDelay

    }
    
    @discardableResult
    func set(newState: SrtCallerStates) -> SrtCallerState {
        
        print("setting caller state to \(newState.label)")
        self._state = newState.instance
        return self._state
        
    }
    
}
