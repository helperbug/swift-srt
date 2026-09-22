//
//  KeyMaterialFrame.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation

/// The Keying Material message, byte for byte as haicrypt lays it out:
///
///     0: version (high nibble) | packet type (low nibble)   = 0x12
///   1-2: signature 0x2029 ("HAI"), big-endian
///     3: key flags in the low two bits (01 even, 10 odd, 11 both)
///   4-7: KEK index, big-endian (0: derive from the passphrase)
///     8: cipher (2: AES-CTR)
///     9: auth (0: none)
///    10: stream encapsulation (2: MPEG-TS/SRT)
/// 11-13: reserved
///    14: salt length / 4
///    15: key length / 4
///   16+: salt, then the wrapped key(s): 8 byte check value + n keys
public struct KeyMaterialFrame: ByteFrame {

    public enum KeyFlags: UInt8, Sendable {
        case even = 0b01
        case odd = 0b10
        case both = 0b11

        public var keyCount: Int { self == .both ? 2 : 1 }
    }

    public static let version: UInt8 = 1
    public static let packetType: UInt8 = 2
    public static let signature: UInt16 = 0x2029
    public static let cipherAesCtr: UInt8 = 2
    public static let streamEncapsulationTsSrt: UInt8 = 2
    public static let saltOffset = 16

    public let data: Data

    public var version: UInt8 { data[0] >> 4 }
    public var packetType: UInt8 { data[0] & 0x0F }
    public var signature: UInt16 { UInt16(data[1]) << 8 | UInt16(data[2]) }
    public var keyFlags: KeyFlags { KeyFlags(rawValue: data[3] & 0x03) ?? .even }
    public var kekIndex: UInt32 { var offset = 4; return data.toUInt32(from: &offset) }
    public var cipher: UInt8 { data[8] }
    public var auth: UInt8 { data[9] }
    public var streamEncapsulation: UInt8 { data[10] }
    public var saltLength: Int { Int(data[14]) * 4 }
    public var keyLength: Int { Int(data[15]) * 4 }

    public var salt: Data {
        Data(data[Self.saltOffset ..< Self.saltOffset + saltLength])
    }

    public var wrappedKey: Data {
        let start = Self.saltOffset + saltLength
        return Data(data[start ..< start + SrtCrypto.keyWrapOverhead + keyFlags.keyCount * keyLength])
    }

    /// Every length here is peer supplied; the message is rejected unless it
    /// is exactly the size its own header says, with the checks libsrt makes.
    public init?(_ bytes: Data) {

        guard bytes.count > Self.saltOffset else { return nil }
        self.data = Data(bytes)

        guard version == Self.version, packetType == Self.packetType, signature == Self.signature else { return nil }
        guard KeyFlags(rawValue: data[3] & 0x03) != nil else { return nil }
        guard saltLength <= SrtCrypto.saltLength, [16, 24, 32].contains(keyLength) else { return nil }

        let expected = Self.saltOffset + saltLength + SrtCrypto.keyWrapOverhead + keyFlags.keyCount * keyLength
        guard data.count == expected else { return nil }
    }

    public init(keyFlags: KeyFlags, keyLength: Int, salt: Data, wrappedKey: Data, kekIndex: UInt32 = 0) {
        var bytes = Data(capacity: Self.saltOffset + salt.count + wrappedKey.count)
        bytes.append(Self.version << 4 | Self.packetType)
        bytes.append(contentsOf: Self.signature.bytes)
        bytes.append(keyFlags.rawValue)
        bytes.append(contentsOf: kekIndex.bytes)
        bytes.append(Self.cipherAesCtr)
        bytes.append(0)                                   // auth: none
        bytes.append(Self.streamEncapsulationTsSrt)
        bytes.append(contentsOf: [0, 0, 0])               // reserved
        bytes.append(UInt8(salt.count / 4))
        bytes.append(UInt8(keyLength / 4))
        bytes.append(salt)
        bytes.append(wrappedKey)
        self.data = bytes
    }

    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }
}
