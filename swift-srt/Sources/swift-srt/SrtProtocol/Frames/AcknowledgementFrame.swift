//
//  AcknowledgementFrame.swift
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

/// Acknowledgment (ACK) control packets are used to provide the delivery status of data packets. By acknowledging the reception of data packets up to the acknowledged packet sequence number, the receiver notifies the sender that all prior packets were received or, in the case of live streaming, preceding missing packets (if any) were dropped as too late to be delivered.
///
/// There are several types of ACK packets:¶
/// A Full ACK control packet is sent every 10 ms and has all the fields of Figure 14.
/// A Light ACK control packet includes only the Last Acknowledged Packet Sequence Number field. The Type-specific Information field should be set to 0.
/// A Small ACK includes the fields up to and including the Available Buffer Size field. The Type-specific Information field should be set to 0.
/// The sender only acknowledges the receipt of Full ACK packets (see Section 3.2.8).
/// The Light ACK and Small ACK packets are used in cases when the receiver should acknowledge received data packets more often than every 10 ms. This is usually needed at high data rates. It is up to the receiver to decide the condition and the type of ACK packet to send (Light or Small). The recommendation is to send a Light ACK for every 64 packets received.
///
/// ![Acknowledgement](acknowledgement-frame)
///

public struct AcknowledgementFrame: ByteFrame {

    public let data: Data

    /// The packet type value of an ACK control packet is "1".
    public var isControl: Bool {
        return (data[0] & 0b10000000) != 0
    }

    /// The control type value of an ACK control packet is "2".
    public var controlType: ControlTypes {
        let rawValue = UInt16(data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian) & 0x7FFF
        
        return ControlTypes(rawValue: rawValue) ?? .none
    }

    /// Future
    public var reserved: UInt16 {
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// This field contains the sequential number of the full acknowledgment packet starting from 1, except in the case of Light ACKs and Small ACKs, where this value is 0 (see below).
    public var acknowledgementNumber: UInt32 {
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public var timestamp: UInt32 {
        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public var destinationSocketID: UInt32 {
        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// This field contains the sequence number of the last data packet being acknowledged plus one. In other words, if it the sequence number of the first unacknowledged packet.
    public var lastAcknowledgedPacketSequenceNumber: UInt32 {
        return data.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// RTT value, in microseconds, estimated by the receiver based on the previous ACK/ACKACK packet pair exchange.
    public var rtt: UInt32 {
        return data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// The variance of the RTT estimate, in microseconds.
    public var rttVariance: UInt32 {
        return data.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Available size of the receiver's buffer, in packets.
    public var availableBufferSize: UInt32 {
        return data.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// The rate at which packets are being received, in packets per second.
    public var packetsReceivingRate: UInt32 {
        return data.subdata(in: 32..<36).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Estimated bandwidth of the link, in packets per second.
    public var estimatedLinkCapacity: UInt32 {
        return data.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Estimated receiving rate, in bytes per second.
    public var receivingRate: UInt32 {
        return data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        guard bytes.count >= 44 else { return nil }
        
        self.data = bytes
    }

    /// Constructor used when sending over the network
    public init(
        isControl: Bool,
        controlType: ControlTypes,
        reserved: UInt16,
        acknowledgementNumber: UInt32,
        timestamp: UInt32,
        destinationSocketID: UInt32,
        lastAcknowledgedPacketSequenceNumber: UInt32,
        rtt: UInt32,
        rttVariance: UInt32,
        availableBufferSize: UInt32,
        packetsReceivingRate: UInt32,
        estimatedLinkCapacity: UInt32,
        receivingRate: UInt32
    ) {
        var data = Data(capacity: 44)

        let header = UInt16(isControl ? 0x8000 : 0x0000) | (controlType.rawValue & 0x7FFF)
        data.append(contentsOf: withUnsafeBytes(of: header.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: reserved.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: acknowledgementNumber.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: destinationSocketID.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: lastAcknowledgedPacketSequenceNumber.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: rtt.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: rttVariance.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: availableBufferSize.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: packetsReceivingRate.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: estimatedLinkCapacity.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: receivingRate.bigEndian, Array.init))

        self.data = data
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket
    {
        SrtPacket(
            field1: ControlTypes.acknowledgement.asField,
            socketID: socketId,
            contents: self.data
        )
    }

}
