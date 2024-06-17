//
//  SrtReceiveMessageProtocol.swift
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

protocol SrtReceiveMessageProtocol {
    
    var ackAckCount: Int { get }
    var ackCount: Int { get }
    var duration: TimeInterval { get }
    var nackCount: Int { get }
    var totalBytes: Int { get }

    var onMessageReceived: (UInt32, Data) -> Void { get }
    var sendAck: (UInt32) -> Void { get }
    var sendNack: ([UInt32], [(UInt32, UInt32)]) -> Void { get }

    func handleAckAck (ackAck: AckAckFrame) -> Void
    func receivePacket(packet: DataPacketFrame)

    init(
        encryptionKey: Data,
        decryptionKey: Data,
        messageId: UInt32,
        sequenceNumberBase: UInt32,
        onMessageReceived: @escaping (UInt32, Data) -> Void,
        sendAck: @escaping (UInt32) -> Void,
        sendNack: @escaping ([UInt32], [(UInt32, UInt32)]) -> Void
    )
}
