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
    
    let srtSocketID: UInt32
    let initialPacketSequenceNumber: UInt32
    let synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool
    let send: (SrtPacket, Data) -> Void
    let onSocketCreated: (SrtSocketProtocol) -> Void

    private var state: SrtListenerState
    
    init(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        send: @escaping (SrtPacket, Data) -> Void,
        onSocketCreated: @escaping (SrtSocketProtocol) -> Void
    ) {
        self.srtSocketID = srtSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self.state = StrListenerInducedState()
        self.send = send
        self.onSocketCreated = onSocketCreated
        
        self.state.auto(self)
    }
    
    func handleHandshake(handshake: SrtHandshake) {
        
        self.state.handleHandshake(self, handshake: handshake)
        
    }
    
    @discardableResult
    func set(newState: SrtListenerStates) -> SrtListenerState {
        
        print("setting listener state to \(newState.label)")
        self.state = newState.instance
        return self.state
        
    }
    
}
