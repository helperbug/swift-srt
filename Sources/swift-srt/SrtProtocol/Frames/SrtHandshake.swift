//
//  SrtHandshake.swift
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

import CryptoKit
import Foundation
import Network

/// Represents a handshake control packet used to exchange peer configurations, agree on connection parameters, and establish a connection.
public struct SrtHandshake {
    // public let data: Data
    
    /// The handshake version number. Currently used values are 4 and 5. Values greater than 5 are reserved for future use.
    public let hsVersion: HandshakeVersions
    
    /// Block cipher family and key size. The default value is 0 (no encryption advertised). If neither peer advertises encryption, AES-128 is selected by default.
    public let encryptionField: UInt16
    
    /// Message specific extension related to Handshake Type field. Must be set to 0 except for specific messages like INDUCTION or CONCLUSION.
    public let extensionField: UInt16
    
    /// The sequence number of the very first data packet to be sent.
    public let initialPacketSequenceNumber: UInt32
    
    /// Maximum Transmission Unit (MTU) size, in bytes. This value is typically set to 1500 bytes.
    public let maximumTransmissionUnitSize: UInt32
    
    /// The maximum number of data packets allowed to be "in flight".
    public let maximumFlowWindowSize: UInt32
    
    /// Indicates the handshake packet type.
    public let handshakeType: HandshakeTypes
    
    /// ID of the source SRT socket from which a handshake packet is issued.
    public let srtSocketID: UInt32
    
    /// Randomized value used for processing a handshake.
    public let synCookie: UInt32
    
    /// IPv4 or IPv6 address of the packet's sender.
    public let peerIPAddress: Data
    
    /// Used to process an integrated handshake extension.
    public let extensionType: HandshakeExtensionTypes
    
    /// The length of the Extension Contents field in four-byte blocks.
    public let extensionLength: UInt16
    
    /// The payload of the extension.
    public let extensionContents: Data
    
    public let extensions: [HandshakeExtensionTypes: Data]
    
    /// Serializes the struct to Data.
    public var data: Data {
        var data = Data()
        data.append(contentsOf: hsVersion.rawValue.bytes)
        data.append(contentsOf: encryptionField.bytes)
        data.append(contentsOf: extensionField.bytes)
        data.append(contentsOf: initialPacketSequenceNumber.bytes)
        data.append(contentsOf: maximumTransmissionUnitSize.bytes)
        data.append(contentsOf: maximumFlowWindowSize.bytes)
        data.append(contentsOf: handshakeType.rawValue.bytes)
        data.append(contentsOf: srtSocketID.bytes)
        data.append(contentsOf: synCookie.bytes)
        data.append(peerIPAddress)
        
        if extensions.count > 0 {
            /// Extensions are TLVs. A dictionary has no order of its own, so emit them
            /// by ascending type to keep the encoding deterministic — libsrt expects
            /// HSREQ/HSRSP (1, 2) ahead of the KM (3, 4) and config (5+) blocks.
            extensions.sorted { $0.key.rawValue < $1.key.rawValue }.forEach { ext in

                data.append(contentsOf: ext.key.rawValue.bytes)
                data.append(contentsOf: UInt16(ext.value.count / 4).bytes)
                data.append(ext.value)

            }
        } else if extensionType != .none {
            data.append(contentsOf: extensionType.rawValue.bytes)
            data.append(contentsOf: extensionLength.bytes)
            data.append(extensionContents)
        }
        
        return data
    }
    
    /// Initializes a new instance from data.
    public init?(data: Data) {
        var offset = 0
        self.hsVersion = HandshakeVersions(rawValue: data.toUInt32(from: &offset)) ?? .none
        self.encryptionField = data.toUInt16(from: &offset)
        self.extensionField = data.toUInt16(from: &offset)
        self.initialPacketSequenceNumber = data.toUInt32(from: &offset)
        self.maximumTransmissionUnitSize = data.toUInt32(from: &offset)
        self.maximumFlowWindowSize = data.toUInt32(from: &offset)
        let type = HandshakeTypes(rawValue: data.toUInt32(from: &offset)) ?? .done
        self.handshakeType = type
        self.srtSocketID = data.toUInt32(from: &offset)
        self.synCookie = data.toUInt32(from: &offset)
        
        guard offset + 16 <= data.count else {
            return nil
        }
        
        self.peerIPAddress = data.subdata(in: offset..<(offset + 16))
        offset += 16
        
        var extensions: [HandshakeExtensionTypes: Data] = [:]
        
        while offset + 4 <= data.count {
            let extensionType = HandshakeExtensionTypes(rawValue: data.toUInt16(from: &offset)) ?? .none
            let extensionLength = Int(data.toUInt16(from: &offset)) * 4

            /// The length is attacker-controlled, so never read past the buffer.
            guard offset + extensionLength <= data.count else {
                return nil
            }

            extensions[extensionType] = data.subdata(in: offset..<(offset + extensionLength))
            offset += extensionLength
        }
        
        self.extensions = extensions
        
//        if let handshakeExtensionData = extensions[.handshakeRequest] {
//            // self.handshakeExtensionMessage = HandshakeExtensionMessage(handshakeExtensionData)
//        } else {
//            // self.handshakeExtensionMessage = nil
//        }
        
        self.extensionType = .none
        self.extensionLength = UInt16(0)
        self.extensionContents = Data()
    }
    
    var isInductionRequest: Bool {
        hsVersion == .version4 &&
        encryptionField == 0 &&
        extensionField == 2 &&
        handshakeType == .induction &&
        srtSocketID != 0 &&
        synCookie == 0
    }
    
    var isInductionResponse: Bool {
        hsVersion == .version5 &&
        extensionField == 0x4A17 &&
        handshakeType == .induction &&
        srtSocketID != 0 &&
        synCookie != 0
    }
    
    /// A conclusion request always carries HSREQ; KMREQ and CONFIG are optional,
    /// so match on the HSREQ bit rather than on one exact extension field value.
    /// The request echoes back the cookie the listener handed out during induction.
    func isConclusionRequest(synCookie reference: UInt32) -> Bool {
        hsVersion == .version5 &&
        extensionField & UInt16(HandshakeExtensionFlagTypes.handshakeRequest.rawValue) != 0 &&
        handshakeType == .conclusion &&
        srtSocketID != 0 &&
        synCookie == reference &&
        extensions[.handshakeResponse] == nil
    }

    /// The listener answers with an HSRSP extension and no cookie, which is what
    /// separates a conclusion response from the request that provoked it.
    var isConclusionResponse: Bool {
        hsVersion == .version5 &&
        handshakeType == .conclusion &&
        srtSocketID != 0 &&
        (extensions[.handshakeResponse] != nil || extensionType == .handshakeResponse)
    }

}

public extension SrtHandshake {
    init(
        hsVersion: HandshakeVersions,
        encryptionField: UInt16,
        extensionField: UInt16,
        initialPacketSequenceNumber: UInt32,
        maximumTransmissionUnitSize: UInt32,
        maximumFlowWindowSize: UInt32,
        handshakeType: HandshakeTypes,
        srtSocketID: UInt32,
        synCookie: UInt32,
        peerIPAddress: Data,
        extensionType: HandshakeExtensionTypes,
        extensionLength: UInt16,
        extensionContents: Data,
        extensions: [HandshakeExtensionTypes: Data] = [:]
    ) {
        self.hsVersion = hsVersion
        self.encryptionField = encryptionField
        self.extensionField = extensionField
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.maximumTransmissionUnitSize = maximumTransmissionUnitSize
        self.maximumFlowWindowSize = maximumFlowWindowSize
        self.handshakeType = handshakeType
        self.srtSocketID = srtSocketID
        self.synCookie = synCookie
        self.peerIPAddress = peerIPAddress
        self.extensionType = extensionType
        self.extensionLength = extensionLength
        self.extensionContents = extensionContents
        self.extensions = extensions
    }
    
    /// The listener's answer to an induction request: version 5, the magic
    /// extension value, the cookie, and the key size it will require (0 for
    /// none). Key material itself only travels in the conclusion exchange.
    static func makeInductionResponse(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encryptionField: UInt16 = 0
    ) -> SrtHandshake {

        return SrtHandshake(
            hsVersion: .version5,
            encryptionField: encryptionField,
            extensionField: 0x4A17, // SRT Magic Value
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .induction,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: peerIpAddress,
            extensionType: .none,
            extensionLength: 0,
            extensionContents: Data()
        )
    }

    /// Smallest MTU that still leaves room for an SRT header on top of UDP/IPv4.
    /// A peer advertising less than this would size payload buffers to nothing.
    static let minimumTransmissionUnitSize: UInt32 = 76

    /// Largest MTU worth honouring; beyond this a peer is asking us to allocate
    /// buffers out of proportion to any real path.
    static let maximumTransmissionUnitSize: UInt32 = 65536

    /// Payload bytes left once the UDP/IPv4 and SRT headers are accounted for.
    var usablePayloadSize: Int {
        Int(maximumTransmissionUnitSize) - 28 - 16
    }

    /// Peer-supplied transmission parameters have to be usable before anything
    /// sizes a buffer from them.
    var hasUsableTransmissionParameters: Bool {
        maximumTransmissionUnitSize >= Self.minimumTransmissionUnitSize &&
        maximumTransmissionUnitSize <= Self.maximumTransmissionUnitSize &&
        maximumFlowWindowSize > 0
    }

    /// SRT version this package advertises, formed as major * 0x10000 + minor * 0x100 + patch.
    /// Tracks libsrt 1.5.7 (2026-08-27).
    static let srtLibraryVersion: UInt32 = 0x00010507

    /// TSBPDSND | TSBPDRCV | CRYPT | TLPKTDROP | PERIODICNAK | REXMITFLG | STREAM as libsrt sends them.
    static let defaultSrtFlags: UInt32 = 0xbf

    /// Latency budget in milliseconds.
    static let defaultTsbpdDelay: UInt16 = 120

    /// The extension field is a bitmap of which extension groups follow, so it has
    /// to be derived from the extensions actually being sent rather than hardcoded.
    static func extensionField(for extensions: [HandshakeExtensionTypes: Data]) -> UInt16 {

        var field: UInt32 = 0

        for type in extensions.keys {
            switch type {
            case .handshakeRequest, .handshakeResponse:
                field |= HandshakeExtensionFlagTypes.handshakeRequest.rawValue
            case .keyMaterialRequest, .keyMaterialResponse:
                field |= HandshakeExtensionFlagTypes.keyMaterialRequest.rawValue
            case .streamId, .congestionControl, .filterControl, .groupControl:
                field |= HandshakeExtensionFlagTypes.configuration.rawValue
            case .none:
                break
            }
        }

        return UInt16(field)
    }

    static func makeConclusionRequest(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        extensions: [HandshakeExtensionTypes: Data],
        encryptionField: UInt16 = 0
    ) -> SrtHandshake {

        return SrtHandshake(
            hsVersion: .version5,
            encryptionField: encryptionField,
            extensionField: extensionField(for: extensions),
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .conclusion,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: peerIpAddress,
            extensionType: .none,
            extensionLength: 0,
            extensionContents: Data(),
            extensions: extensions
        )
    }

    /// The Handshake Extension Message MUST be present in the conclusion response,
    /// carried as HSRSP. The response does not echo the cookie back.
    static func makeConclusionResponse(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        keyMaterialResponse: Data? = nil,
        encryptionField: UInt16 = 0
    ) -> SrtHandshake {

        let hsrsp = HandshakeExtensionMessage(
            srtVersion: Self.srtLibraryVersion,
            srtFlags: Self.defaultSrtFlags,
            receiverTsbpdDelay: Self.defaultTsbpdDelay,
            senderTsbpdDelay: Self.defaultTsbpdDelay
        )

        var extensions: [HandshakeExtensionTypes: Data] = [.handshakeResponse: hsrsp.data]
        if let keyMaterialResponse {
            extensions[.keyMaterialResponse] = keyMaterialResponse
        }

        return SrtHandshake(
            hsVersion: .version5,
            encryptionField: encryptionField,
            extensionField: extensionField(for: extensions),
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .conclusion,
            srtSocketID: srtSocketID,
            synCookie: 0,
            peerIPAddress: peerIpAddress,
            extensionType: .none,
            extensionLength: 0,
            extensionContents: Data(),
            extensions: extensions
        )
    }
    
    
    private static func generateSynCookie(clientIP: String, clientPort: UInt16, serverIP: String, serverPort: UInt16, mss: UInt8 = 5) -> UInt32 {

        let currentTime = UInt32(Date().timeIntervalSince1970) / 64
        let timestamp = UInt8(currentTime % 32)

        print("timeIntervalSince1970 \(UInt32(Date().timeIntervalSince1970)), currentTime \(currentTime), timestamp \(timestamp)")
        
        var concatenatedData = Data()
        concatenatedData.append(contentsOf: serverIP.split(separator: ".").compactMap { UInt8($0) })
        concatenatedData.append(contentsOf: withUnsafeBytes(of: serverPort.bigEndian) { Data($0) })
        concatenatedData.append(contentsOf: clientIP.split(separator: ".").compactMap { UInt8($0) })
        concatenatedData.append(contentsOf: withUnsafeBytes(of: clientPort.bigEndian) { Data($0) })
        concatenatedData.append(contentsOf: [timestamp])

        // Generate cryptographic hash (bottom 24 bits)
        let hash = SHA256.hash(data: concatenatedData)
        let hash24Bits = hash.prefix(3).reduce(0) { (result, byte) in (result << 8) | UInt32(byte) }

        // Combine t (timestamp), m (MSS), and s (hash) to form the SYN cookie
        let result = (UInt32(timestamp) << 27) | (UInt32(mss) << 24) | (hash24Bits & 0x00FFFFFF)
        let binaryString = String(result, radix: 2)

        print("MSS is \(mss)")
        print("Result (bits): \(binaryString)")
        
        return result
    }

    
    func makePacket(socketId: UInt32) -> SrtPacket
    {
        SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: socketId,
            contents: self.data
        )
    }

}

extension SrtHandshake {
    
    
    /// Rendezvous opener: HSv5, our advertised key size, no extension flags
    /// (not the magic value -- libsrt does not parse a wave that carries it),
    /// and our cookie for the contest.
    static func makeWaveAHand(srtSocketID: UInt32, initialPacketSequenceNumber: UInt32, cookie: UInt32,
                              peerIpAddress: Data, encryptionField: UInt16 = 0) -> SrtHandshake {
        SrtHandshake(
            hsVersion: .version5,
            encryptionField: encryptionField,
            extensionField: 0,
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .waveAHand,
            srtSocketID: srtSocketID,
            synCookie: cookie,
            peerIPAddress: peerIpAddress,
            extensionType: .none, extensionLength: 0, extensionContents: Data()
        )
    }

    /// Rendezvous closer from the initiator: no extensions, nothing to negotiate.
    static func makeAgreement(srtSocketID: UInt32, initialPacketSequenceNumber: UInt32, peerIpAddress: Data) -> SrtHandshake {
        SrtHandshake(
            hsVersion: .version5,
            encryptionField: 0,
            extensionField: 0,
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .agreement,
            srtSocketID: srtSocketID,
            synCookie: 0,
            peerIPAddress: peerIpAddress,
            extensionType: .none, extensionLength: 0, extensionContents: Data()
        )
    }

    static func makeInductionRequest(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32 = 0,
        serverIpAddress: Data
    ) -> SrtHandshake {

        return SrtHandshake(
            hsVersion: .version4,
            encryptionField: 0,
            extensionField: 2,
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .induction,
            srtSocketID: srtSocketID,
            synCookie: 0,
            peerIPAddress: serverIpAddress,
            extensionType: .none,
            extensionLength: 0,
            extensionContents: Data()
        )
    }

}

extension SrtHandshake {
    /// SRT version formed as major * 0x10000 + minor * 0x100 + patch
    public var srtVersion: UInt32? {
        if let data = extensions[.handshakeRequest], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        } else if let data = extensions[.handshakeResponse], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// SRT configuration flags
    public var srtFlags: UInt32? {
        if let data = extensions[.handshakeRequest], data.count >= 8 {
            return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        } else if let data = extensions[.handshakeResponse], data.count >= 8 {
            return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Receiver's TSBPD delay in milliseconds
    public var receiverTsbpdDelay: UInt16? {
        if let data = extensions[.handshakeRequest], data.count >= 10 {
            return data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        } else if let data = extensions[.handshakeResponse], data.count >= 10 {
            return data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        }
        return nil
    }
    
    /// Sender's TSBPD delay in milliseconds
    public var senderTsbpdDelay: UInt16? {
        if let data = extensions[.handshakeRequest], data.count >= 12 {
            return data.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        } else if let data = extensions[.handshakeResponse], data.count >= 12 {
            return data.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        }
        return nil
    }
    
    /// Version of the key material request
    public var keyMaterialVersion: UInt32? {
        if let data = extensions[.keyMaterialRequest], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Encryption type of the key material request
    public var keyMaterialEncryptionType: UInt32? {
        if let data = extensions[.keyMaterialRequest], data.count >= 8 {
            return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Length of the key in the key material request
    public var keyMaterialKeyLength: UInt16? {
        if let data = extensions[.keyMaterialRequest], data.count >= 10 {
            return data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        }
        return nil
    }
    
    /// Type of key wrap in the key material request
    public var keyMaterialWrapType: UInt16? {
        if let data = extensions[.keyMaterialRequest], data.count >= 12 {
            return data.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        }
        return nil
    }
    
    /// Encrypted key in the key material request
    public var keyMaterialEncryptedKey: Data? {
        if let data = extensions[.keyMaterialRequest], data.count > 12 {
            return data.subdata(in: 12..<data.count)
        }
        return nil
    }
    
    /// libsrt copies byte-array extensions (stream id, key material) through a
    /// 32-bit host-to-network conversion, which on a little-endian host reverses
    /// the bytes within every word. It is its own inverse.
    static func wordReversed(_ data: Data) -> Data {
        var out = Data(capacity: data.count)
        let whole = data.count - data.count % 4
        for start in stride(from: 0, to: whole, by: 4) {
            out.append(contentsOf: data[data.startIndex + start ..< data.startIndex + start + 4].reversed())
        }
        out.append(data.suffix(from: data.startIndex + whole))
        return out
    }

    /// Key material goes on the wire as haicrypt lays it out -- libsrt does not
    /// word-reverse it the way it does the stream id. A message that only
    /// parses word-reversed is accepted anyway and noted, so a peer that does
    /// it the other way still connects and the difference is visible.
    static func keyMaterial(_ raw: Data) -> Data? {
        if raw.count == 4 { return raw }
        if raw.count > 3, raw[raw.startIndex] == KeyMaterialFrame.version << 4 | KeyMaterialFrame.packetType,
           raw[raw.startIndex + 1] == 0x20, raw[raw.startIndex + 2] == 0x29 {
            return raw
        }
        let reversed = wordReversed(raw)
        if reversed.count > 3, reversed[0] == KeyMaterialFrame.version << 4 | KeyMaterialFrame.packetType,
           reversed[1] == 0x20, reversed[2] == 0x29 {
            print("Handshake: key material arrived word-reversed; accepting")
            return reversed
        }
        return raw
    }

    public var keyMaterialRequest: Data? {
        extensions[.keyMaterialRequest].flatMap(Self.keyMaterial)
    }

    public var keyMaterialResponse: Data? {
        extensions[.keyMaterialResponse].flatMap(Self.keyMaterial)
    }

    /// StreamID is used to identify a path. libsrt stores it as 32-bit words with
    /// the bytes reversed inside each word, zero padded to a word boundary, so the
    /// reversal has to be undone before the bytes read as text.
    public var streamId: String? {
        guard let encoded = extensions[.streamId], !encoded.isEmpty else {
            return nil
        }

        var bytes = Data(capacity: encoded.count)
        for start in stride(from: 0, to: encoded.count - (encoded.count % 4), by: 4) {
            bytes.append(contentsOf: encoded[encoded.startIndex + start ..< encoded.startIndex + start + 4].reversed())
        }

        /// Trailing padding is zero bytes, and a short id leaves them inside the word.
        while bytes.last == 0 {
            bytes.removeLast()
        }

        return String(data: bytes, encoding: .utf8)
    }
    
    /// Type of congestion control
    public var congestionControlType: UInt32? {
        if let data = extensions[.congestionControl], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Information for congestion control
    public var congestionControlInfo: Data? {
        if let data = extensions[.congestionControl], data.count > 4 {
            return data.subdata(in: 4..<data.count)
        }
        return nil
    }
    
    /// Type of filter control
    public var filterControlType: UInt32? {
        if let data = extensions[.filterControl], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Information for filter control
    public var filterControlInfo: Data? {
        if let data = extensions[.filterControl], data.count > 4 {
            return data.subdata(in: 4..<data.count)
        }
        return nil
    }
    
    /// Group ID
    public var groupId: UInt32? {
        if let data = extensions[.groupControl], data.count >= 4 {
            return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
    /// Flags for group control
    public var groupFlags: UInt32? {
        if let data = extensions[.groupControl], data.count >= 8 {
            return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        }
        return nil
    }
    
}
