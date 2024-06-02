//
//  NegativeAckFrame.swift
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

/// Negative acknowledgment (NAK) control packets are used to signal failed data packet deliveries. The receiver notifies the sender about lost data packets by sending a NAK packet that contains a list of sequence numbers for those lost packets.
public struct NegativeAckFrame: ByteFrame {
    func makePacket(socketId: UInt32) -> SrtPacket {
        return .blank
    }
    public let data: Data

    /// The packet type value of a NAK control packet is "1".
    public var isControl: Bool {
        (data[0] & 0b10000000) != 0
    }

    /// The control type value of a NAK control packet is "3".
    public var controlType: UInt16 {
        UInt16(data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian) & 0x7FFF
    }

    /// Reserved for future use, always 0.
    public var reserved: UInt16 {
        data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// Reserved for future definition.
    public var typeSpecificInformation: UInt32 {
        data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Timestamp of the NAK packet.
    public var timestamp: UInt32 {
        data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Destination SRT Socket ID.
    public var destinationSocketID: UInt32 {
        data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Control Information Field (CIF) that includes a list of lost packet sequence numbers.
    public var lossList: [UInt32] {
        // Parsing the loss list, assuming starting at byte index 16.
        // Actual implementation would depend on the specific encoding of the list.
        var losses = [UInt32]()
        var index = 16
        while index + 4 <= data.count {
            let sequenceNumber = data.subdata(in: index..<index+4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            losses.append(sequenceNumber)
            index += 4
        }
        return losses
    }

    /// Constructor for initializing with data.
    public init?(_ bytes: Data) {
        guard bytes.count >= 16 else { return nil }
        self.data = bytes
    }

    /// Constructor for creating a NAK frame to be sent over the network.
    public init(
        isControl: Bool,
        controlType: UInt16,
        reserved: UInt16 = 0,
        typeSpecificInformation: UInt32 = 0,
        timestamp: UInt32,
        destinationSocketID: UInt32,
        lossList: [UInt32]
    ) {
        var data = Data(capacity: 16 + lossList.count * 4)
        let header = UInt16(isControl ? 0x8000 : 0x0000) | (controlType & 0x7FFF)
        data.append(contentsOf: withUnsafeBytes(of: header.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: reserved.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: typeSpecificInformation.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: destinationSocketID.bigEndian, Array.init))
        
        for number in lossList {
            data.append(contentsOf: withUnsafeBytes(of: number.bigEndian, Array.init))
        }

        self.data = data
    }
}
