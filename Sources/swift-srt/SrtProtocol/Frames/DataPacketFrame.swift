//
//  DataPacketFrame.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
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
        let val = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0x7FFFFFFF
        
        return val
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

    /// Payload: variable length. AES-CTR adds no tag, so encrypted and clear
    /// packets carry data right to the end.
    public var payload: Data {
        data.subdata(in: 16..<data.count)
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

        /// PP occupies bits 31-30, O bit 29, KK bits 28-27, R bit 26 and the
        /// message number the remaining 26 bits.
        let messageNumberWithFlags = (UInt32(packetPosition & 0b11) << 30) |
                                     (orderFlag ? (1 << 29) : 0) |
                                     (UInt32(encryptionFlags & 0b11) << 27) |
                                     (retransmittedFlag ? (1 << 26) : 0) |
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
        /// The first word of a data packet is its sequence number, and the second
        /// carries the flags and message number -- not a control type.
        SrtPacket(
            isData: true,
            field1: packetSequenceNumber,
            field2: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian,
            timestamp: timestamp,
            socketID: socketId,
            contents: payload
        )
    }

    static var blank: DataPacketFrame {
        DataPacketFrame(packetSequenceNumber: 0,
                        packetPosition: 0,
                        orderFlag: false,
                        encryptionFlags: 0,
                        retransmittedFlag: false,
                        messageNumber: 0,
                        timestamp: UInt32(Date().timeIntervalSince1970),
                        destinationSocketID: 0,
                        payload: .init(),
                        authenticationTag: .init())
    }
    
}
