//
//  SrtReceiveMessageContext
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
import CryptoKit

class SrtReceiveMessageContext: SrtReceiveMessageProtocol {
    var ackAckCount: Int = 0
    var ackCount: Int = 0
    var duration: TimeInterval = 0
    var nackCount: Int = 0
    var totalBytes: Int = 0
    
    var onMessageReceived: (UInt32, Data) -> Void
    var sendAck: (UInt32) -> Void
    var sendNack: ([UInt32], [(UInt32, UInt32)]) -> Void

    private var packets: [Data]
    private let encryptionKey: SymmetricKey
    private let decryptionKey: SymmetricKey
    private let sequenceNumberBase: UInt32
    private let messageId: UInt32
    private var highestDelta: UInt32 = 0

    required init(
        encryptionKey: Data,
        decryptionKey: Data,
        messageId: UInt32,
        sequenceNumberBase: UInt32,
        onMessageReceived: @escaping (UInt32, Data) -> Void,
        sendAck: @escaping (UInt32) -> Void,
        sendNack: @escaping ([UInt32], [(UInt32, UInt32)]) -> Void
    ) {
        
        self.encryptionKey = SymmetricKey(data: encryptionKey)
        self.decryptionKey = SymmetricKey(data: decryptionKey)
        self.messageId = messageId
        self.sequenceNumberBase = sequenceNumberBase
        self.onMessageReceived = onMessageReceived
        self.sendAck = sendAck
        self.sendNack = sendNack
        self.packets = Array(repeating: Data(repeating: 0, count: 1364), count: 500)

    }

    func receivePacket(packet: DataPacketFrame) {
        
        let index = Int(packet.packetSequenceNumber - sequenceNumberBase)
        packets[index] = packet.data
        highestDelta = max(highestDelta, UInt32(index))
        totalBytes += packet.data.count

        if packet.packetSequenceNumber % 15 == 0 {
            sendAck(packet.packetSequenceNumber)
            ackCount += 1
        }

        if nackCount % 7 == 0 {
            let lostPacketSequenceNumbers = detectLostPackets()
            let rangeOfLostPackets = detectRangesOfLostPackets()
            sendNack(lostPacketSequenceNumbers, rangeOfLostPackets)
            nackCount += 1
        }
        
        if packet.packetPosition == 2 {
           //  self.onMessageReceived(Data())
        }
        
    }

    func handleAckAck(ackAck: AckAckFrame) {
        
        ackAckCount += 1

    }

    private func detectLostPackets() -> [UInt32] {

        var lostPackets: [UInt32] = []
        
        for (index, packet) in packets.enumerated() {
            if packet.isEmpty {
                lostPackets.append(UInt32(index) + sequenceNumberBase)
            }
        }

        return lostPackets

    }

    private func detectRangesOfLostPackets() -> [(UInt32, UInt32)] {

        var ranges: [(UInt32, UInt32)] = []
        var start: Int? = nil

        for (index, packet) in packets.enumerated() {
            if packet.isEmpty {
                if start == nil {
                    start = index
                }
            } else if let s = start {
                // ranges.append((UInt32(s + sequenceNumberBase), UInt32(index + sequenceNumberBase - 1)))
                start = nil
            }
        }
        
        if let s = start {
            // ranges.append((UInt32(s + sequenceNumberBase), UInt32(packets.count + sequenceNumberBase - 1)))
        }

        return ranges

    }
}
