//
//  SrtPacket.swift
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

public struct SrtPacket {
    
    let data: Data
    
    var isData: Bool {
        
        guard data.count > 0 else {
            return false
        }
        
        return (data[0] & 0b10000000) == 0
        
    }
    
    var field1: UInt32 {
        
        guard data.count > 15 else {
            return 0
        }
        
        return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian & 0xEFFFFFF

    }
    
    var field2: UInt32 {

        guard data.count > 15 else {
            return 0
        }
        
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
    
    var timestamp: UInt32 {

        guard data.count > 15 else {
            return 0
        }

        return data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    var destinationSocketID: UInt32 {

        guard data.count > 15 else {
            return 0
        }

        return data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

    }
    
    var contents: Data {

        guard data.count > 15 else {
            return Data()
        }

        return data.subdata(in: 16..<data.count)

    }
    
    init(isData: Bool = false, field1: UInt32, field2: UInt32 = 0, socketID: UInt32, contents: Data) {
        let timestamp: UInt32 = UInt32(Date().timeIntervalSince1970)
        
        var data = Data(capacity: 16 + contents.count)
        
        let field1WithIsData = (field1 & 0x7FFFFFFF) | (isData ? 0x00000000 : 0x80000000)
        var field1BigEndian = field1WithIsData.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &field1BigEndian) { Data($0) })

        var field2BigEndian = field2.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &field2BigEndian) { Data($0) })
        
        var timestampBigEndian = timestamp.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestampBigEndian) { Data($0) })
        
        var socketIdBigEndian = socketID.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &socketIdBigEndian) { Data($0) })

        data.append(contents)
        
        self.data = data
    }
    
    init(data: Data) {
        self.data = data
    }
    
    public static var blank: SrtPacket {
        SrtPacket(
            isData: false,
            field1: 0,
            field2: 0,
            socketID: 0,
            contents: Data()
        )
    }
}
