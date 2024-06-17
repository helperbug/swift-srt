//
//  SrtSendMessageContext
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

import CryptoKit
import Foundation

class SrtSendMessageContext: SrtSendMessageProtocol {
    var ackAckCount: Int = 0
    var ackCount: Int = 0
    var duration: TimeInterval = .init()
    var nackCount: Int = 0
    var totalBytes: Int = 0
    
    var onMessageSent: (UInt32) -> Void
    var sendAckAck: (UInt32) -> Void
    var sendData: (DataPacketFrame) -> Void

    private var packets: [DataPacketFrame]
    private let encryptionKey: SymmetricKey
    private let decryptionKey: SymmetricKey
    private let destinationSocketId: UInt32
    private let sequenceNumberBase: UInt32
    private let messageId: UInt32
    private var highestDelta: UInt32 = 0
    
    required init(
        frame: Data,
        encryptionKey: Data,
        decryptionKey: Data,
        messageId: UInt32,
        destinationSocketId: UInt32,
        sequenceNumberBase: UInt32,
        sendAckAck: @escaping (UInt32) -> Void,
        sendData: @escaping (DataPacketFrame) -> Void,
        onMessageSent: @escaping (UInt32) -> Void
    ) {
        self.encryptionKey = SymmetricKey(data: encryptionKey)
        self.decryptionKey = SymmetricKey(data: decryptionKey)
        self.messageId = messageId
        self.destinationSocketId = destinationSocketId
        self.sequenceNumberBase = sequenceNumberBase
        self.sendAckAck = sendAckAck
        self.sendData = sendData
        self.onMessageSent = onMessageSent
        self.packets = Self.chunkData(socketId: destinationSocketId,
                                      messageId: messageId,
                                      frame: frame,
                                      starting: sequenceNumberBase)
    }

    private static func chunkData(socketId: UInt32,
                                  messageId: UInt32,
                                  frame: Data,
                                  starting sequenceNumber: UInt32) -> [DataPacketFrame] {
        let chunkSize = 1364
        let totalChunks = Int(ceil(Double(frame.count) / Double(chunkSize)))
        var chunks: [DataPacketFrame] = Array(repeating: .blank, count: totalChunks)
        
        for i in 0..<totalChunks {
            let start = i * chunkSize
            let end = min(start + chunkSize, frame.count)
            let chunk = frame[start..<end]
            let packetSequenceNumber = sequenceNumber + UInt32(i)
            let packetPosition: UInt8 = i == 0 ? 0b01 : (i == totalChunks - 1 ? 0b10 : 0b00)
            let dataPacket = DataPacketFrame(
                packetSequenceNumber: packetSequenceNumber,
                packetPosition: packetPosition,
                orderFlag: false,
                encryptionFlags: 0,
                retransmittedFlag: false,
                messageNumber: messageId,
                timestamp: UInt32(Date().timeIntervalSince1970),
                destinationSocketID: socketId,
                payload: chunk,
                authenticationTag: Data()
            )

            chunks[i] = dataPacket

        }
        
        return chunks
    }

    func handleAck(ack: AcknowledgementFrame) {
        ackCount += 1
    }

    func handleNack(nack: NegativeAckFrame) {
        nackCount += 1
    }
}
