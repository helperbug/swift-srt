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
        
        let inductionRepsonse = makeInductionResponse(srtSocketID: context.srtSocketID,
                                                      initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                                                      synCookie: context.synCookie,
                                                      peerIpAddress: context.peerIpAddress,
                                                      encrypted: context.encrypted)
        
        let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: context.srtSocketID, contents: Data())
        let contents = inductionRepsonse.makePacket(socketId: context.srtSocketID).contents
        
        context.send(packet, contents)
        context.set(newState: .inductionResponding)
        
    }
    
    private func makeInductionResponse(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool
    ) -> SrtHandshake {
        
        let keyMaterial = IntegrityCheckVectorFrame.makeWrapper()
        
        let keyMaterialFrame = KeyMaterialFrame(
            version: 1,
            packetType: 2,
            sign: 0x4841, // HAI signature
            keyEncryption: 0b11, // Both even and odd keys are provided
            keki: 0,
            cipher: 2, // AES-CTR
            auth: 0, // None
            streamEncapsulation: 2, // MPEG-TS/SRT
            saltLength: 16 / 4,
            keyLength: 32 / 4,
            salt: Data.random(16),
            wrappedKey: keyMaterial.data
        )
        
        if encrypted {
            
            return SrtHandshake(
                hsVersion: .version5,
                encryptionField: 0x0004, // AES-256
                extensionField: 0x4A17, // SRT Magic Value
                initialPacketSequenceNumber: initialPacketSequenceNumber,
                maximumTransmissionUnitSize: 1500,
                maximumFlowWindowSize: 8192,
                handshakeType: .induction,
                srtSocketID: srtSocketID,
                synCookie: synCookie,
                peerIPAddress: peerIpAddress,
                extensionType: .keyMaterialResponse,
                extensionLength: UInt16(keyMaterialFrame.data.count / 4),
                extensionContents: keyMaterialFrame.data
            )
            
        } else {
            
            return SrtHandshake(
                hsVersion: .version5,
                encryptionField: 0x0000, // None
                extensionField: 0x4A17, // SRT Magic Value
                initialPacketSequenceNumber: initialPacketSequenceNumber,
                maximumTransmissionUnitSize: 1500,
                maximumFlowWindowSize: 8192,
                handshakeType: .induction,
                srtSocketID: srtSocketID,
                synCookie: synCookie,
                peerIPAddress: peerIpAddress,
                extensionType: .none,
                extensionLength: 0,
                extensionContents: Data()
            )
            
        }
        
    }
}
