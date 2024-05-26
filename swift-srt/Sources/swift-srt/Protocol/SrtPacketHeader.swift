//
//  SrtPacketHeader.swift
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

public struct SrtPacketHeader {
    let isControl: Bool
    let flagAndPacketTypeDependentField1: UInt32
    let packetTypeDependentField2: UInt32
    let timestamp: UInt32
    let destinationSocketID: UInt32
    let contentLength: Int

    init(isControl: Bool, data: Data) {
        self.isControl = isControl
        self.flagAndPacketTypeDependentField1 = isControl ? 0x80000000 : 0x00000000
        self.packetTypeDependentField2 = 0
        self.timestamp = UInt32(Date().timeIntervalSince1970)
        self.destinationSocketID = 0
        self.contentLength = data.count
    }

    init(_ buffer: UnsafeRawBufferPointer) {
        let alignedBuffer = Data(buffer)
        
        var cursor = 0
        
        let flagAndPacketTypeDependentField1 = alignedBuffer.toUInt32(from: &cursor)
        let isData = (flagAndPacketTypeDependentField1 >> 31) & 1 == 0
        
        self.isControl = isData
        self.flagAndPacketTypeDependentField1 = flagAndPacketTypeDependentField1 & 0x7FFFFFFF
        
        packetTypeDependentField2 = alignedBuffer.toUInt32(from: &cursor)
        
        timestamp = alignedBuffer.toUInt32(from: &cursor)
        
        destinationSocketID = alignedBuffer.toUInt32(from: &cursor)
        
        contentLength = buffer.count - Self.encodedSize
    }

    public var flag: UInt8 {
        return UInt8((flagAndPacketTypeDependentField1 >> 24) & 0xFF)
    }

    public var packetTypeDependentField1: UInt32 {
        return flagAndPacketTypeDependentField1 & 0x00FFFFFF
    }

    public var encodedData: Data {
        var data = Data()
        var networkOrder = flagAndPacketTypeDependentField1.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &networkOrder) { Data($0) })
        
        networkOrder = packetTypeDependentField2.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &networkOrder) { Data($0) })

        networkOrder = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &networkOrder) { Data($0) })

        networkOrder = destinationSocketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &networkOrder) { Data($0) })

        return data
    }

    static var encodedSize: Int {
        return MemoryLayout<UInt32>.size * 4
    }
}
