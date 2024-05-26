//
//  NegativeAcknowledgementFrame.swift
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

/// Negative acknowledgment (NAK) control packets are used to signal failed data packet deliveries.
/// The receiver notifies the sender about lost data packets by sending a NAK packet that contains a list of sequence numbers for those lost packets.
public struct NegativeAcknowledgementFrame: ByteFrame {

    /// Byte representation of the frame
    public let data: Data

    /// Packet Type: 1 bit, value = 1. The packet type value of a NAK control packet is "1".
    public var isControl: Bool {
        return (data[0] & 0b10000000) == 1
    }

    /// Control Type: 15 bits, value = NAK{0x0003}. The control type value of a NAK control packet is "3".
    public var controlType: UInt16 {
        return data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian & 0x7FFF
    }

    /// Reserved field
    public var reserved: UInt16 {
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// Type-specific Information (reserved for future definition)
    public var typeSpecificInformation: UInt32 {
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Timestamp: 32 bits
    public var timestamp: UInt32 {
        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Destination SRT Socket ID: 32 bits
    public var destinationSocketID: UInt32 {
        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Control Information Field (CIF): A single value or a range of lost packets sequence numbers
    public var lossList: [UInt32] {
        var result: [UInt32] = []
        var offset = 16
        while offset < data.count {
            let value = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            result.append(value)
            offset += 4
        }
        return result
    }

    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        guard bytes.count >= 16 else {
            return nil
        }

        self.data = bytes

        guard isControl else {
            return nil
        }

        guard controlType == 3 else {
            return nil
        }
    }

    /// Constructor used when sending over the network
    public init(
        controlType: UInt16 = 3,
        reserved: UInt16 = 0,
        typeSpecificInformation: UInt32,
        timestamp: UInt32 = UInt32(Date().timeIntervalSince1970),
        destinationSocketID: UInt32,
        lossList: [UInt32]
    ) {
        var data = Data(capacity: 16 + lossList.count * 4)

        let controlTypeWithPacketType = (controlType & 0x7FFF) | 0x8000
        var controlTypeBigEndian = controlTypeWithPacketType.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &controlTypeBigEndian) { Data($0) })

        var reservedBigEndian = reserved.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &reservedBigEndian) { Data($0) })

        var typeSpecificInformationBigEndian = typeSpecificInformation.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &typeSpecificInformationBigEndian) { Data($0) })

        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })

        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })

        for lost in lossList {
            var lostBigEndian = lost.bigEndian
            data.append(contentsOf: withUnsafeBytes(of: &lostBigEndian) { Data($0) })
        }

        self.data = data
    }

}
