//
//  MessageDropRequestFrame.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 5/25/2024.
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

/// A Message Drop Request control packet is sent by the sender to the receiver when a retransmission of an unacknowledged packet (forming a whole or a part of a message) which is not present in the sender's buffer is requested. This may happen, for example, when a TTL parameter (passed in the sending function) triggers a timeout for retransmitting one or more lost packets which constitute parts of a message, causing these packets to be removed from the sender's buffer.
///
/// The sender notifies the receiver that it must not wait for retransmission of this message. Note that a Message Drop Request control packet is not sent if the Too Late Packet Drop mechanism (Section 4.6) causes the sender to drop a message, as in this case the receiver is expected to drop it anyway.
/// A Message Drop Request contains the message number and corresponding range of packet sequence numbers which form the whole message. If the sender does not already have in its buffer the specific packet or packets for which retransmission was requested, then it is unable to restore the message number. In this case the Message Number field must be set to zero, and the receiver should drop packets in the provided packet sequence number range.
///
/// ![Message Drop Request Map](Resources/MessageDropRequestMap.png)

public struct MessageDropRequestFrame: ByteFrame {
    
    /// Byte representation of the frame
    public let data: Data
    
    /// Packet Type: 1 bit, value = 1. The packet type value of a Drop Request control packet is "1"
    public var isControl: Bool {
        return (data[0] & 0b10000000) == 1
    }
    
    /// Control Type: 15 bits, value = 7. The control type value of a Drop Request control packet is "7".
    public var controlType: UInt16 {
        return data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian & 0xEF
    }
    
    /// Reserved always zero
    public var reserved: UInt16 {
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// The identifying number of the message requested to be dropped. See the Message Number field in Section 3.1.
    public var messageNumber: UInt32 {

        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
    
    public var timestamp: UInt32 {

        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }

    public var destinationSocketID: UInt32 {

        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    /// The sequence number of the first packet in the message.
    public var firstSequenceNumber: UInt32 {

        return data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0xEFFF

    }
    
    /// The sequence number of the last packet in the message.
    public var lastSequenceNumber: UInt32 {

        return data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0xEFFF

    }
    
    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        
        guard bytes.count == 24 else {
            return nil
        }
        
        self.data = bytes
        
        guard isControl, controlType == 7 else { return nil }
    }
    
    /// Constructor used when sending over the network
    public init(
        controlType: UInt16 = 7,
        reserved: UInt16 = 0,
        messageNumber: UInt32,
        timestamp: UInt32 = UInt32(Date().timeIntervalSince1970),
        destinationSocketID: UInt32,
        firstSequenceNumber: UInt32,
        lastSequenceNumber: UInt32
    ) {
        var data = Data(capacity: 24)
        
        let controlTypeWithPacketType = (controlType & 0x7FFF) | 0x8000
        var controlTypeBigEndian = controlTypeWithPacketType.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &controlTypeBigEndian) { Data($0) })
        
        var reservedBigEndian = reserved.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &reservedBigEndian) { Data($0) })
        
        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })
        
        var firstSequenceNumberBigEndian = firstSequenceNumber.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &firstSequenceNumberBigEndian) { Data($0) })
        
        var lastSequenceNumberBigEndian = lastSequenceNumber.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &lastSequenceNumberBigEndian) { Data($0) })
        
        self.data = data
    }
}
