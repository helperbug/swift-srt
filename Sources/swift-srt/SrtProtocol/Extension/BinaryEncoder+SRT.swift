//
//  BinaryEncoder+SRT.swift
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

struct BinaryEncoder {
    static func encode<T>(_ value: T) -> Data where T: FixedWidthInteger {
        var mutableValue = value.bigEndian
        return Data(bytes: &mutableValue, count: MemoryLayout<T>.size)
    }

    static func decode<T>(_ type: T.Type, from data: Data) -> T? where T: FixedWidthInteger {
        guard data.count == MemoryLayout<T>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: T.self).bigEndian }
    }
}

extension BinaryEncoder {
    static func encodeArray<T>(_ array: [T]) -> Data where T: FixedWidthInteger {
        var data = Data()
        array.forEach { value in
            data.append(encode(value))
        }
        return data
    }

    static func decodeArray<T>(_ type: T.Type, from data: Data, count: Int) -> [T]? where T: FixedWidthInteger {
        var result = [T]()
        var offset = 0
        for _ in 0..<count {
            guard let value = decode(T.self, from: data[offset..<offset + MemoryLayout<T>.size]) else {
                return nil
            }
            result.append(value)
            offset += MemoryLayout<T>.size
        }
        return result
    }
}
