//
//  ControlPacketFrame.swift
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

public struct ControlPacketFrame: ByteFrame {

    public let data: Data

    /// Control Type: 15 bits
    public var controlType: UInt16 {
        return UInt16(data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian) & 0x7FFF
    }

    /// Subtype: 16 bits
    public var subtype: UInt16 {
        return data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// Type-specific Information: 32 bits
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

    /// Control Information Field (CIF): variable length
    public var controlInformationField: Data {
        return data.subdata(in: 16..<data.count)
    }

    public var controlPacketType: ControlTypes
    
   
    public init?(_ bytes: Data) {
        guard bytes.count >= 16 else {
            return nil
        }
        
        let rawControlType = UInt16(bytes.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian) & 0x7FFF
        
        guard let controlType = ControlTypes(rawValue: rawControlType) else {
            return nil
        }

        self.controlPacketType = controlType
        
        self.data = bytes
        
        print("Socket ID: \(self.destinationSocketID)")
        print(String(format: "%02X", self.destinationSocketID))
    }

    /// Constructor used when sending over the network
    public init(
        controlType: UInt16,
        subtype: UInt16,
        typeSpecificInformation: UInt32,
        timestamp: UInt32,
        destinationSocketID: UInt32,
        controlInformationField: Data
    ) {
        var data = Data(capacity: 16 + controlInformationField.count)

        var header = (controlType & 0x7FFF) << 16 | (subtype & 0xFFFF)
        data.append(contentsOf: withUnsafeBytes(of: &header) { Data($0) })

        var typeSpecificInfoBigEndian = typeSpecificInformation.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &typeSpecificInfoBigEndian) { Data($0) })

        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })

        var destinationSocketIDBigEndian = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &destinationSocketIDBigEndian) { Data($0) })

        data.append(controlInformationField)

        self.controlPacketType = ControlTypes(rawValue: controlType) ?? .none
        
        self.data = data
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }

}
