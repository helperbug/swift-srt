//
//  StrListenerInductedState.swift
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

struct StrListenerInductedState: SrtListenerState {
    
    let name: SrtListenerStates = .inducted
    
    func auto(_ context: SrtListenerContext) {
        
        let conclusionResponse = makeConclusionResponse(srtSocketID: context.srtSocketID,
                                                        initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                                                        synCookie: context.synCookie,
                                                        peerIpAddress: context.peerIpAddress)
        
        let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: context.srtSocketID, contents: Data())
        let contents = conclusionResponse.makePacket(socketId: context.srtSocketID).contents
        
        context.send(packet, contents)

        let socket = SrtSocketContext(encrypted: context.encrypted,
                                      socketId: context.srtSocketID,
                                      synCookie: context.synCookie)
        
        context.onSocketCreated(socket)
        
        context.set(newState: .active)
        
    }
    
    private func makeConclusionResponse(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data
    ) -> SrtHandshake {
        
        let handshakeExt = HandshakeExtensionMessage(srtVersion: 0x00010502,
                                                     srtFlags: 0xbf,
                                                     receiverTsbpdDelay: 120,
                                                     senderTsbpdDelay: 120)
        
        let contents = handshakeExt.data
        
        return SrtHandshake(
            hsVersion: .version5,
            encryptionField: 0, // No encryption
            extensionField: 1,
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .conclusion,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: peerIpAddress,
            extensionType: .handshakeResponse,
            extensionLength: UInt16(contents.count / 4),
            extensionContents: contents
        )
    }

}
