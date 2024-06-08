//
//  DataPacketFrame.swift
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

/// Data packets are used to transmit the actual content in SRT protocol
public struct DataPacketFrame: ByteFrame {

    
    /// Byte representation of the frame
    public let data: Data

    /// Packet Type: 1 bit, value = 0. The packet type value of a data packet is "0".
    public var isData: Bool {
        return (data[0] & 0b10000000) == 0
    }

    /// The sequential number of the data packet. Range [0; 2^31 - 1].
    public var packetSequenceNumber: UInt32 {
        return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0x7FFFFFFF
    }

    /// This field indicates the position of the data packet in the message. The value "10b" (binary) means the first packet of the message. "00b" indicates a packet in the middle. "01b" designates the last packet. If a single data packet forms the whole message, the value is "11b".
    public var packetPosition: UInt8 {
        return (data[4] & 0b11000000) >> 6
    }

    /// Indicates whether the message should be delivered by the receiver in order (1) or not (0). Certain restrictions apply depending on the data transmission mode used (Section 4.2).
    public var orderFlag: Bool {
        return (data[4] & 0b00100000) != 0
    }

    /// Key-based Encryption Flag. The flag bits indicate whether or not data is encrypted. The value "00b" (binary) means data is not encrypted. "01b" indicates that data is encrypted with an even key, and "10b" is used for odd key encryption. Refer to Section 6. The value "11b" is only used in control packets.
    public var encryptionFlags: UInt8 {
        return (data[4] & 0b00011000) >> 3
    }

    /// This flag is clear when a packet is transmitted the first time. The flag is set to "1" when a packet is retransmitted.
    public var retransmittedFlag: Bool {
        return (data[4] & 0b00000100) != 0
    }

    /// The sequential number of consecutive data packets that form a message (see PP field).
    public var messageNumber: UInt32 {
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0x03FFFFFF
    }

    public var timestamp: UInt32 {
        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public var destinationSocketID: UInt32 {
        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Payload: variable length.
    public var payload: Data {
        
        if encryptionFlags == 1 || encryptionFlags == 2 {

            let index = data.count - 16
            
            return data.subdata(in: 16..<index)

        } else {

            return data.subdata(in: 16..<data.count)

        }

    }

    public var authenticationTag: Data? {
        
        guard encryptionFlags == 1 || encryptionFlags == 2 else {
            return nil
        }

        guard data.count > 32 else {
            return nil
        }
        
        let index = data.count - 16

        return data.subdata(in: index..<data.count)
    }

    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        guard bytes.count >= 16 else {
            return nil
        }

        self.data = bytes

        guard isData else {
            return nil
        }
        
//        guard authenticationTag != nil,
//              bytes.count >= 32 else {
//            return nil
//        }
    }

    /// Constructor used when sending over the network
    public init(
        packetSequenceNumber: UInt32,
        packetPosition: UInt8,
        orderFlag: Bool,
        encryptionFlags: UInt8,
        retransmittedFlag: Bool,
        messageNumber: UInt32,
        timestamp: UInt32,
        destinationSocketID: UInt32,
        payload: Data,
        authenticationTag: Data
    ) {
        var data = Data(capacity: 16 + payload.count)

        let packetSequenceNumberWithFlag = (packetSequenceNumber & 0x7FFFFFFF)
        var packetSequenceNumberBigEndian = packetSequenceNumberWithFlag.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &packetSequenceNumberBigEndian) { Data($0) })

        let messageNumberWithFlags = (UInt32(packetPosition) << 30) |
                                     (orderFlag ? 0b00100000 : 0) |
                                     (UInt32(encryptionFlags) << 3) |
                                     (retransmittedFlag ? 0b00000100 : 0) |
                                     (messageNumber & 0x03FFFFFF)
        var messageNumberBigEndian = messageNumberWithFlags.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &messageNumberBigEndian) { Data($0) })

        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })

        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })

        data.append(payload)
        data.append(authenticationTag)

        self.data = data
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket
    {
        SrtPacket(
            isData: true,
            field1: ControlTypes.ackack.asField,
            socketID: socketId,
            contents: self.data
        )
    }

    static var blank: DataPacketFrame {
        DataPacketFrame(packetSequenceNumber: 0,
                        packetPosition: 0,
                        orderFlag: false,
                        encryptionFlags: 0,
                        retransmittedFlag: false,
                        messageNumber: 0,
                        timestamp: 0,
                        destinationSocketID: 0,
                        payload: .init(),
                        authenticationTag: .init())
    }
    
}
