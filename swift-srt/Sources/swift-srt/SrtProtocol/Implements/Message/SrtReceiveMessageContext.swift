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
