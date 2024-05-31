//
//  SrtHandshake.swift
//
//
//  Created by Ben Waidhofer on 5/4/24.
//

import CryptoKit
import Foundation
import Network

/// Represents a handshake control packet used to exchange peer configurations, agree on connection parameters, and establish a connection.
public struct SrtHandshake {
    // public let data: Data
    
    /// The handshake version number. Currently used values are 4 and 5. Values greater than 5 are reserved for future use.
    public let hsVersion: UInt32
    
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
    public let handshakeType: HandshakeType
    
    /// ID of the source SRT socket from which a handshake packet is issued.
    public let srtSocketID: UInt32
    
    /// Randomized value used for processing a handshake.
    public let synCookie: UInt32
    
    /// IPv4 or IPv6 address of the packet's sender.
    public let peerIPAddress: Data
    
    /// Used to process an integrated handshake extension.
    public let extensionType: UInt16
    
    /// The length of the Extension Contents field in four-byte blocks.
    public let extensionLength: UInt16
    
    /// The payload of the extension.
    public let extensionContents: Data
    
    /// Serializes the struct to Data.
    public var data: Data {
        var data = Data()
        data.append(contentsOf: hsVersion.bytes)
        data.append(contentsOf: encryptionField.bytes)
        data.append(contentsOf: extensionField.bytes)
        data.append(contentsOf: initialPacketSequenceNumber.bytes)
        data.append(contentsOf: maximumTransmissionUnitSize.bytes)
        data.append(contentsOf: maximumFlowWindowSize.bytes)
        data.append(contentsOf: handshakeType.rawValue.bytes)
        data.append(contentsOf: srtSocketID.bytes)
        data.append(contentsOf: synCookie.bytes)
        data.append(peerIPAddress)
        return data
//        data.append(contentsOf: extensionType.bytes)
//        data.append(contentsOf: extensionLength.bytes)
//        data.append(extensionContents)
//        return data
    }

    func toData() -> Data {
           var data = Data()
           data.append(BinaryEncoder.encode(hsVersion))
           data.append(BinaryEncoder.encode(encryptionField))
           data.append(BinaryEncoder.encode(extensionField))
           data.append(BinaryEncoder.encode(initialPacketSequenceNumber))
           data.append(BinaryEncoder.encode(maximumTransmissionUnitSize))
           data.append(BinaryEncoder.encode(maximumFlowWindowSize))
           data.append(contentsOf: handshakeType.rawValue.bigEndian.bytes)
           data.append(BinaryEncoder.encode(srtSocketID))
           data.append(BinaryEncoder.encode(synCookie))
           data.append(peerIPAddress)
           data.append(BinaryEncoder.encode(extensionType))
           data.append(BinaryEncoder.encode(extensionLength))
           return data
       }
    
    /// Initializes a new instance from data.
    public init?(data: Data) {
        var offset = 0
        self.hsVersion = data.toUInt32(from: &offset)
        self.encryptionField = data.toUInt16(from: &offset)
        self.extensionField = data.toUInt16(from: &offset)
        self.initialPacketSequenceNumber = data.toUInt32(from: &offset)
        self.maximumTransmissionUnitSize = data.toUInt32(from: &offset)
        self.maximumFlowWindowSize = data.toUInt32(from: &offset)
        let type = HandshakeType(rawValue: data.toUInt32(from: &offset)) ?? HandshakeType.done
        self.handshakeType = type
        self.srtSocketID = data.toUInt32(from: &offset)
        self.synCookie = data.toUInt32(from: &offset)
        guard offset + 16 <= data.count else {
            return nil
        }
        self.peerIPAddress = data.subdata(in: offset..<(offset + 16))
        offset += 16
        
        if offset + 4 <= data.count {
            self.extensionType = data.toUInt16(from: &offset)
            self.extensionLength = data.toUInt16(from: &offset)
            self.extensionContents = data.subdata(in: offset..<data.count)
        } else {
            self.extensionType = UInt16(0)
            self.extensionLength = UInt16(0)
            self.extensionContents = Data()
        }
    }
    
    /// Enumerates the possible types of handshakes in the SRT protocol.
    public enum HandshakeType: UInt32, CaseIterable {
        case done = 0xFFFFFFFD
        case agreement = 0xFFFFFFFE
        case conclusion = 0xFFFFFFFF
        case waveAHand = 0x00000000
        case induction = 0x00000001
    }
    
    var isInductionRequest: Bool {
        hsVersion == 4 &&
        encryptionField == 0 &&
        extensionField == 2 &&
        handshakeType == .induction &&
        srtSocketID != 0 &&
        synCookie == 0
    }
}

public extension SrtHandshake {
    init(
        hsVersion: UInt32,
        encryptionField: UInt16,
        extensionField: UInt16,
        initialPacketSequenceNumber: UInt32,
        maximumTransmissionUnitSize: UInt32,
        maximumFlowWindowSize: UInt32,
        handshakeType: HandshakeType,
        srtSocketID: UInt32,
        synCookie: UInt32,
        peerIPAddress: Data,
        extensionType: UInt16,
        extensionLength: UInt16,
        extensionContents: Data
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
    }
    
    static func makeInductionResponse4(srtSocketID: UInt32, host: String, port: UInt16) -> SrtHandshake {
        let synCookie = generateSynCookie(clientIP: host, clientPort: port, serverIP: "127.0.0.1", serverPort: 1900)
        
        return SrtHandshake(
            hsVersion: 5,
            encryptionField: 0x0005, // AES-256
            extensionField: 0x4A17,
            initialPacketSequenceNumber: 0,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .induction,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: Data([1, 0, 0, 127, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            extensionType: 0,
            extensionLength: 0,
            extensionContents: Data()
        )
    }
    
    static func makeInductionResponse(srtSocketID: UInt32, synCookie: UInt32, peerIpAddress: Data) -> SrtHandshake {
        let keyMaterial = IntegrityCheckVectorFrame.makeWrapper()
        
        let keyMaterialFrame = KeyMaterialFrame(
            version: 1,
            packetType: 2,
            sign: 0x4841, // HAI signature
            keyEncryption: 0b11, // Both even and odd keys are provided
            keki: 0,
            cipher: 2, // AES-CTR
            auth: 0, // None
            streamEncapsulation: 2, // MPEG-TS/SRT
            saltLength: 16 / 4,
            keyLength: 32 / 4,
            salt: Data.random(16),
            wrappedKey: keyMaterial.data
        )

        return SrtHandshake(
            hsVersion: 5,
            encryptionField: 0x0005, // AES-256
            extensionField: 0x4A17, // SRT Magic Value
            initialPacketSequenceNumber: 0,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .induction,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: peerIpAddress,
            extensionType: 2,
            extensionLength: UInt16(keyMaterialFrame.data.count / 4),
            extensionContents: keyMaterialFrame.data
        )
    }
    
    private static func generateSynCookie(clientIP: String, clientPort: UInt16, serverIP: String, serverPort: UInt16, mss: UInt8 = 5) -> UInt32 {
        // Generate the timestamp (top 5 bits)
        let currentTime = UInt32(Date().timeIntervalSince1970) / 64
        let timestamp = UInt8(currentTime % 32)

        print("timeIntervalSince1970 \(UInt32(Date().timeIntervalSince1970)), currentTime \(currentTime), timestamp \(timestamp)")
        
        // Create a binary representation of the concatenated values
        var concatenatedData = Data()
//        concatenatedData.append(contentsOf: serverIP.split(separator: ".").compactMap { UInt8($0) })
//        concatenatedData.append(contentsOf: withUnsafeBytes(of: serverPort) { Data($0) })
//        concatenatedData.append(contentsOf: clientIP.split(separator: ".").compactMap { UInt8($0) })
//        concatenatedData.append(contentsOf: withUnsafeBytes(of: clientPort) { Data($0) })
//        concatenatedData.append(contentsOf: [timestamp])
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


}

extension SrtHandshake {
    
    
    static func makeInductionRequest(server: IPAddress) -> SrtHandshake {

        return SrtHandshake(
            hsVersion: 4,
            encryptionField: 0,
            extensionField: 2,
            initialPacketSequenceNumber: 0,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .induction,
            srtSocketID: UInt32.random(in: UInt32.min...UInt32.max),
            synCookie: 0,
            peerIPAddress: server.toData(),
            extensionType: 0,
            extensionLength: 0,
            extensionContents: Data()
        )
    }
    
}