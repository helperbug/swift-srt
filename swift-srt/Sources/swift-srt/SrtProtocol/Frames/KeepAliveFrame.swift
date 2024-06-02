//
//  KeepAliveFrame.swift
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

/// Keep-alive control packets are sent after a certain timeout from the last time any packet (Control or Data) was sent. The purpose of this control packet is to notify the peer to keep the connection open when no data exchange is taking place.
/// The default timeout for a keep-alive packet to be sent is 1 second.
public struct KeepAliveFrame: ByteFrame {
    
    public let data: Data

    /// The packet type value of a keep-alive control packet is "1".
    public var isControl: Bool {
        return (data[0] & 0b10000000) != 0
    }

    /// The control type value of a keep-alive control packet is "1"
    public var controlType: UInt16 {
        return UInt16(data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian) & 0x7FFF
    }

    /// This is a fixed-width field reserved for future use.
    public var reserved: UInt16 {
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// This field is reserved for future definition.
    public var typeSpecificInformation: UInt32 {
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public var timestamp: UInt32 {
        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public var destinationSocketID: UInt32 {
        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    public init?(_ bytes: Data) {

        guard bytes.count == 16 else { return nil }

        self.data = bytes

    }

    /// Constructor used when sending over the network
    public init(
        controlType: UInt16,
        reserved: UInt16,
        typeSpecificInformation: UInt32,
        timestamp: UInt32,
        destinationSocketID: UInt32
    ) {
        var data = Data(capacity: 16)

        var header = (controlType & 0x7FFF)
        data.append(contentsOf: withUnsafeBytes(of: &header) { Data($0) })

        var reservedBigEndian = reserved.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &reservedBigEndian) { Data($0) })

        var typeSpecificInfoBigEndian = typeSpecificInformation.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &typeSpecificInfoBigEndian) { Data($0) })

        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })

        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })

        self.data = data
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket
    {
        SrtPacket(
            field1: ControlTypes.keepAlive.asField,
            socketID: socketId,
            contents: self.data
        )
    }

}
