//
//  BinaryEncoder.swift
//
//
//  Created by Ben Waidhofer on 5/5/24.
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
