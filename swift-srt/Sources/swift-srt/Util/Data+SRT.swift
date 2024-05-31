//
//  Data+SRT.swift
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

extension Data {
    
    var asHexArray: String {
        var rows: [String] = []
        var counter = 0
        var row = ""
        
        for value in self {
            row += String(format: "%02X", value) + " "
            counter += 1
            
            if counter == 4 {
                row += " "
            }
            
            if counter == 8 {
                counter = 0
                rows.append(row)
                row = ""
            }
        }
        
        return rows.joined(separator: "\n")
    }
    
    func toUInt32(from offset: inout Int) -> UInt32 {
        let size = MemoryLayout<UInt32>.size
        defer { offset += size }
        return self.subdata(in: offset..<(offset + size)).reversed().withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    func toUInt16(from offset: inout Int) -> UInt16 {
        let size = MemoryLayout<UInt16>.size
        defer { offset += size }
        return self.subdata(in: offset..<(offset + size)).reversed().withUnsafeBytes { $0.load(as: UInt16.self) }
    }
    
    subscript(range: Range<Int>) -> Data {
        return self.subdata(in: range)
    }
    
    static func random(_ length: Int) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: 0...255) })
    }
}
