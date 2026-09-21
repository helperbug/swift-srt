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

/// The purpose of the Key Material Message is to let peers exchange encryption-related information to be used to encrypt and decrypt the payload of the stream.
///
/// This message can be supplied in two possible ways:
///
/// as a Handshake Extension (see Section 3.2.1.2)
///
/// in the Content Information Field of the User-Defined control packet (described below).
///
/// When the Key Material is transmitted as a control packet, the Control Type field of the SRT packet header is set to User-Defined Type (see Table 1), the Subtype field of the header is set to SRT_CMD_KMREQ for key-refresh request and SRT_CMD_KMRSP for key-refresh response (Table 5). The KM Refresh mechanism is described in Section 6.1.6.
///
/// The structure of the Key Material message is illustrated in Figure 11.
public struct KeyMaterialFrame: ByteFrame {

    public let data: Data

    /// Future
    public var reserved: Bool {
        return data[0] == 0x80
    }

    /// This is a fixed-width 3-bit field that indicates the KM message version.
    public var version: UInt8 {
        return (data[0] & 0b01110000) >> 4
    }

    /// This is a fixed-width field that indicates the Packet Type:
    /// 0: Reserved
    /// 1: Media Stream Message (MSmsg)
    /// 2: Keying Material Message (KMmsg)
    /// 7: Reserved to discriminate MPEG-TS packet (0x47=sync byte).
    public var packetType: UInt8 {
        return (data[0] >> 4) & 0x0F
    }

    /// This is a fixed-width field that contains the signature ‘HAI‘ encoded as a PnP Vendor ID [PNPID] (in big-endian order).
    public var sign: UInt16 {
        return data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian } & 0x7FF
    }

    /// This is a fixed-width field reserved for flag extension or other usage.
    public var resv1: UInt8 {
        return data[2] & 0x03
    }

    /// This is a fixed-width field that indicates which SEKs (odd and/or even) are provided in the extension
    /// 00b: No SEK is provided (invalid extension format)
    /// 01b: Even key is provided
    /// 10b: Odd key is provided
    /// 11b: Both even and odd keys are provided.
    public var keyEncryption: UInt8 {
        return data[3] & 0x03
    }

    /// This is a fixed-width field for specifying the Key Encryption Key Index (big-endian order) was used to wrap (and optionally authenticate) the SEK(s). The value 0 is used to indicate the default key of the current stream. Other values are reserved for the possible use of a key management system in the future to retrieve a cryptographic context.
    /// 0: Default stream associated key (stream/system default)
    /// 1..255: Reserved for manually indexed keys.
    public var keki: UInt32 {
        return data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    /// This is a fixed-width field for specifying encryption cipher and mode:¶
    /// 0: None or KEKI indexed crypto contex;
    /// 1: AES-ECB (Reserved, not supported)
    /// 2: AES-CTR [SP800-38A]
    /// 3: AES-CBC (Reserved, not supported)
    /// 4: AES-GCM (Galois Counter Mode), starting from v1.6.0
    /// If AES-GCM is set as the cipher, AES-GCM MUST also be set as the message authentication code algorithm (the Auth field).
    public var cipher: UInt8 {
        return data[7]
    }

    /// This is a fixed-width field for specifying a message authentication code (MAC) algorithm:
    /// 0: None or KEKI indexed crypto context
    /// 1: AES-GCM, starting from v1.6.0.
    /// If AES-GCM is selected as the MAC algorithm, it MUST also be selected as the cipher.
    public var auth: UInt8 {
        return data[8]
    }

    /// This is a fixed-width field for describing the stream encapsulation:
    /// 0: Unspecified or KEKI indexed crypto context
    /// 1: MPEG-TS/UDP
    /// 2: MPEG-TS/SRT.
    public var streamEncapsulation: UInt8 {
        return data[9]
    }

    /// Future
    public var resv2: UInt8 {
        return data[10]
    }

    /// Future
    public var resv3: UInt16 {
        return data.subdata(in: 11..<13).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    }

    /// This is a fixed-width field for specifying salt length SLen in bytes divided by 4. Can be zero if no salt/IV present. The only valid length of salt defined is 128 bits.
    public var saltLength: UInt8 {
        return data[13]
    }

    /// This is a fixed-width field for specifying SEK length in bytes divided by 4. Size of one key even if two keys present. MUST match the key size specified in the Encryption Field of the handshake packet Table 2.
    public var keyLength: UInt8 {
        return data[14]
    }

    /// Byte offset at which the salt begins.
    private static let saltOffset = 15

    /// Salt length in bytes. Widened out of UInt8 before the multiply, which
    /// would otherwise overflow and trap on a peer-supplied value above 63.
    public var saltLengthInBytes: Int {
        Int(saltLength) * 4
    }

    /// Wrapped key length in bytes: n = (KK + 1) / 2 keys of KLen, plus an 8 byte
    /// integrity check vector. Widened for the same reason as the salt.
    public var wrappedKeyLengthInBytes: Int {
        let keyCount = (Int(keyEncryption) + 1) / 2
        return keyCount * Int(keyLength) * 4 + 8
    }

    /// This is a variable-width field that complements the keying material by specifying a salt key.
    public var salt: Data {
        let end = Self.saltOffset + saltLengthInBytes

        guard end <= data.count else {
            return Data()
        }

        return data.subdata(in: Self.saltOffset..<end)
    }

    /// This is a variable-width field for specifying Wrapped key(s), where n = (KK + 1)/2 and the size of the wrap field is ((n * KLen) + 8) bytes.
    public var wrappedKey: Data {
        let start = Self.saltOffset + saltLengthInBytes
        let end = start + wrappedKeyLengthInBytes

        guard start <= data.count, end <= data.count else {
            return Data()
        }

        return data.subdata(in: start..<end)
    }

    /// Constructor used by the receive network path. Every length in a KM message
    /// comes from the peer, so the declared salt and key sizes have to be checked
    /// against the buffer before any field is read.
    public init?(_ data: Data) {

        guard data.count >= Self.saltOffset else { return nil }

        self.data = data

        /// Both keys can only be present if KK says so; 00b is an invalid extension.
        guard keyEncryption != 0 else { return nil }

        let declared = Self.saltOffset + saltLengthInBytes + wrappedKeyLengthInBytes

        guard declared <= data.count else { return nil }

    }

    public init(
        version: UInt8,
        packetType: UInt8,
        sign: UInt16,
        keyEncryption: UInt8,
        keki: UInt32,
        cipher: UInt8,
        auth: UInt8,
        streamEncapsulation: UInt8,
        saltLength: UInt8,
        keyLength: UInt8,
        salt: Data,
        wrappedKey: Data
    ) {
        var buffer = Data(capacity: 15 + Int(saltLength * 4) + Int(((keyEncryption + 1) / 2) * keyLength * 4 + 8))
        
        var header = UInt32(0)
        header |= UInt32(version & 0x07) << 29
        header |= UInt32(packetType & 0x0F) << 25
        header |= UInt32(sign & 0x7FF) << 14
        header |= UInt32(keyEncryption & 0x03) << 12
        buffer.append(contentsOf: withUnsafeBytes(of: header.bigEndian) { Data($0) })

        buffer.append(contentsOf: withUnsafeBytes(of: keki.bigEndian) { Data($0) })
        buffer.append(cipher)
        buffer.append(auth)
        buffer.append(streamEncapsulation)
        buffer.append(UInt8(0)) // Reserved 2
        buffer.append(contentsOf: withUnsafeBytes(of: UInt16(0).bigEndian) { Data($0) }) // Reserved 3
        buffer.append(saltLength / 4)
        buffer.append(keyLength / 4)
        buffer.append(salt)
        buffer.append(wrappedKey)
        
        self.data = buffer
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }
    
}
