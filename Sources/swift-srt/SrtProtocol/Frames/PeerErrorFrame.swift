//
//  PeerErrorFrame.swift
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

/// The Peer Error control packet is sent by a receiver when a processing error (e.g. write to disk failure) occurs. This informs the sender of the situation and unblocks it from waiting for further responses from the receiver.
///
/// The sender receiving this type of control packet must unblock any sending operation in progress. NOTE: This control packet is only used if the File Transfer Congestion Control (Section 5.2) is enabled.

public struct PeerErrorFrame: ByteFrame {

    /// Byte representation of the frame
    public let data: Data
    
    /// Packet Type: 1 bit, value = 1. The packet type value of a Peer Error control packet is "1".
    public var isControl: Bool {
        
        return (data[0] & 0b10000000) == 1
        
    }
    
    /// Control Type: 15 bits, value = 8. The control type value of a Peer Error control packet is "8".
    public var controlType: UInt16 {
        
        return data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian & 0xEFF

    }
    
    /// Reserved
    public var reserved: UInt16 {
        
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian

    }

    /// Error Code: 32 bits. Peer error code. At the moment the only value defined is 4000 - file system error.
    public var errorCode: UInt32 {

        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
    
    /// Timestamp: 32 bits.
    public var timestamp: UInt32 {

        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    /// Destination SRT Socket ID: 32 bits.
    public var destinationSocketID: UInt32 {

        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }

    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        
        guard bytes.count == 16 else {
            return nil
        }
        
        self.data = bytes

        guard isControl else {
            return nil
        }
        
        guard controlType == 8 else {
            return nil
        }
        
        guard errorCode == 4000 else {
            return nil
        }
        
    }
 
    /// Constructor used when sending over the network
    public init(
        isControl: Bool,
        controlType: UInt16,
        reserved: UInt16,
        errorCode: UInt32,
        timestamp: UInt32,
        destinationSocketID: UInt32
    ) {
        var data = Data(capacity: 16)
        
        let controlTypeWithPacketType = (controlType & 0x7FFF) | (isControl ? 0x8000 : 0x0000)
        var controlTypeBigEndian = controlTypeWithPacketType.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &controlTypeBigEndian) { Data($0) })
        
        var reservedBigEndian = reserved.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &reservedBigEndian) { Data($0) })
        
        var errorCodeBigEndian = errorCode.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &errorCodeBigEndian) { Data($0) })
        
        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })
        
        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })
        
        self.data = data
    }

    public func makePacket(socketId: UInt32) -> SrtPacket
    {
        SrtPacket(
            isData: true,
            field1: ControlTypes.peerError.asField,
            socketID: socketId,
            contents: self.data
        )
    }
    
}
