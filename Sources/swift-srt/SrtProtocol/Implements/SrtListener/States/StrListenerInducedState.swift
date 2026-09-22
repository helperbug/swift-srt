//
//  StrListenerInducedState.swift
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

struct StrListenerInducedState: SrtListenerState {
    
    let name: SrtListenerStates = .induced
    
    func auto(_ context: SrtListenerContext) {
        
        let inductionResponse = SrtHandshake.makeInductionResponse(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            synCookie: context.synCookie,
            peerIpAddress: context.peerIpAddress,
            encryptionField: context.passphrase == nil ? 0 : 2
        )

        /// The response is addressed to the caller's socket, while the handshake body
        /// advertises this listener's own socket ID.
        let packet = SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: context.peerSocketID,
            contents: Data()
        )

        /// Advance before transmitting: the conclusion request can arrive at once.
        context.set(newState: .inductionResponding)
        context.send(packet, inductionResponse.data)
        
    }

}
