//
//  SrtSocketProtocol.swift
//
//
//  Created by Ben Waidhofer on 5/26/24.
//

import Combine
import Foundation

/// The SrtSocketProtocol abstracts the details of breaking up frames into data packets, generating metrics, and handling retransmissions. It defines the core properties and methods necessary for interacting with SRT sockets, ensuring consistency and compatibility within the SRT framework.
public protocol SrtSocketProtocol {
    
    /// Whether the socket uses encryption.
    var encrypted: Bool { get }
    
    /// The socket identifier for the user interface
    var id: UUID { get }
    
    /// ID of the source SRT socket.
    var socketId: UInt32 { get }
    
    /// The synCookie that made this socket.
    var synCookie: UInt32 { get }
    
    /// Each full video, audio or still frame is delivered here.
    var onFrameReceived: (Data) -> Void { get }
    
    /// Hints are reported once each second along with the metrics
    var onHintsReceived: ([SrtSocketHints]) -> Void { get }
    
    /// Logs are meant for development time
    var onLogReceived: (String) -> Void { get }
    
    /// Metrics are available at the same time as KeepAlive.
    var onMetricsReceived: ([SrtSocketMetrics]) -> Void { get }
    
    /// Each socket state transition is reported here.
    var onStateChanged: (SrtSocketStates) -> Void { get }
    
    /// Sends the specified data through the SRT socket. The frame will be decomposed into packets and tracked using ACKs and NACKs.
    ///
    /// - Parameter data: The data to be sent.
    func sendFrame(data: Data) -> Void
    
    func handleControl(controlPacket: SrtPacket) -> Result<SrtPacket, SocketError>

    func handleData(packet: DataPacketFrame) -> Void

    /// SRT version formed as major * 0x10000 + minor * 0x100 + patch.
    var srtVersion: UInt32? { get }
    
    /// SRT configuration flags.
    var srtFlags: UInt32? { get }
    
    /// Receiver's TSBPD delay in milliseconds.
    var receiverTsbpdDelay: UInt16? { get }
    
    /// Sender's TSBPD delay in milliseconds.
    var senderTsbpdDelay: UInt16? { get }
    
    /// Version of the key material.
    var keyMaterialVersion: UInt32? { get }
    
    /// Encryption type of the key material.
    var keyMaterialEncryptionType: UInt32? { get }
    
    /// Length of the key in the key material.
    var keyMaterialKeyLength: UInt16? { get }
    
    /// Type of key wrap in the key material.
    var keyMaterialWrapType: UInt16? { get }
    
    /// Encrypted key in the key material.
    var keyMaterialEncryptedKey: Data? { get }
    
    /// Session ID string.
    var streamId: String? { get }
    
    /// Type of filter control.
    var filterControlType: UInt32? { get }
    
    /// Information for filter control.
    var filterControlInfo: Data? { get }
    
    /// Group ID. The identifier of a group whose members include the sender socket that is making a connection.
    var groupId: UInt32? { get }
    
    /// Group type. Group type, as per SRT_GTYPE_ enumeration.
    var groupType: UInt8? { get }
    
    /// Special flags mostly reserved for the future.
    var groupFlags: UInt8? { get }
    
    /// Special value with interpretation depending on the Type field value.
    var groupWeight: UInt16? { get }
    
    /// Initial packet sequence number.
    var initialPacketSequenceNumber: UInt32? { get }
    
    /// Maximum Transmission Unit (MTU) size, in bytes.
    var maximumTransmissionUnitSize: UInt32? { get }
    
    /// The maximum number of data packets allowed to be "in flight".
    var maximumFlowWindowSize: UInt32? { get }
    
    /// Handshake Request frame. This frame includes properties such as SRT version, flags, and TSBPD delays, encoded in a structured format.
    var handshakeRequestExtensionFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Handshake Response extension frame. This frame includes properties such as SRT version, flags, and TSBPD delays, encoded in a structured format.
    var handshakeExtensionResponseFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Key Material Request extension frame. This frame includes properties such as version, encryption type, key length, wrap type, and encrypted key, encoded in a structured format.
    var keyMaterialRequestFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Key Material Response extension frame. This frame includes properties such as version, encryption type, key length, wrap type, and encrypted key, encoded in a structured format.
    var keyMaterialResponseFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Group Membership extension frame. This frame is used to allow multipath SRT connections, including properties such as Group ID, Type, Flags, and Weight.
    var handshakeExtensionGroupFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Session ID frame. This frame identifies the stream content and can be free-form or follow a recommended convention for interoperability.
    /// It is stored as a sequence of UTF-8 characters with a maximum allowed size of 512 bytes.
    var sessionIdFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Filter Control frame.
    var filterControlFrame: [HandshakeExtensionTypes: Data]? { get }
    
    /// Update local properties from these frames
    func update(type: HandshakeExtensionTypes, data: Data) -> Void

    func shutdown() -> Void
    
}

public extension SrtSocketProtocol {
    
    var handshakeExtensionGroupFrame: [HandshakeExtensionTypes: Data]? {
        guard let groupId,
              let groupType,
              let groupFlags,
              let groupWeight else { return nil }
        
        var data = Data()
        data.append(contentsOf: groupId.bigEndian.bytes)
        data.append(contentsOf: groupType.bytes)
        data.append(contentsOf: groupFlags.bytes)
        data.append(contentsOf: groupWeight.bigEndian.bytes)
        
        return [.groupControl: data]
    }
    
    var handshakeExtensionResponseFrame: [HandshakeExtensionTypes: Data]? {
        guard let srtVersion,
              let srtFlags,
              let receiverTsbpdDelay,
              let senderTsbpdDelay else { return nil }
        
        var data = Data()
        data.append(contentsOf: srtVersion.bigEndian.bytes)
        data.append(contentsOf: srtFlags.bigEndian.bytes)
        data.append(contentsOf: receiverTsbpdDelay.bigEndian.bytes)
        data.append(contentsOf: senderTsbpdDelay.bigEndian.bytes)
        
        return [.handshakeResponse: data]
    }
    
    var handshakeRequestExtensionFrame: [HandshakeExtensionTypes: Data]? {
        guard let srtVersion,
              let srtFlags,
              let receiverTsbpdDelay,
              let senderTsbpdDelay else { return nil }
        
        var data = Data()
        data.append(contentsOf: srtVersion.bigEndian.bytes)
        data.append(contentsOf: srtFlags.bigEndian.bytes)
        data.append(contentsOf: receiverTsbpdDelay.bigEndian.bytes)
        data.append(contentsOf: senderTsbpdDelay.bigEndian.bytes)
        
        return [.handshakeRequest: data]
    }
    
    var keyMaterialRequestFrame: [HandshakeExtensionTypes: Data]? {
        guard let keyMaterialVersion,
              let keyMaterialEncryptionType,
              let keyMaterialKeyLength,
              let keyMaterialWrapType,
              let keyMaterialEncryptedKey else { return nil }
        
        var data = Data()
        data.append(contentsOf: keyMaterialVersion.bigEndian.bytes)
        data.append(contentsOf: keyMaterialEncryptionType.bigEndian.bytes)
        data.append(contentsOf: keyMaterialKeyLength.bigEndian.bytes)
        data.append(contentsOf: keyMaterialWrapType.bigEndian.bytes)
        data.append(keyMaterialEncryptedKey)
        
        // Ensure data is padded to the next multiple of 4 bytes
        let paddingLength = (4 - (data.count % 4)) % 4
        if paddingLength > 0 {
            data.append(contentsOf: [UInt8](repeating: 0, count: paddingLength))
        }
        
        return [.keyMaterialRequest: data]
    }
    
    var keyMaterialResponseFrame: [HandshakeExtensionTypes: Data]? {
        guard let keyMaterialVersion,
              let keyMaterialEncryptionType,
              let keyMaterialKeyLength,
              let keyMaterialWrapType,
              let keyMaterialEncryptedKey else { return nil }
        
        var data = Data()
        data.append(contentsOf: keyMaterialVersion.bigEndian.bytes)
        data.append(contentsOf: keyMaterialEncryptionType.bigEndian.bytes)
        data.append(contentsOf: keyMaterialKeyLength.bigEndian.bytes)
        data.append(contentsOf: keyMaterialWrapType.bigEndian.bytes)
        data.append(keyMaterialEncryptedKey)
        
        // Ensure data is padded to the next multiple of 4 bytes
        let paddingLength = (4 - (data.count % 4)) % 4
        if paddingLength > 0 {
            data.append(contentsOf: [UInt8](repeating: 0, count: paddingLength))
        }
        
        return [.keyMaterialResponse: data]
    }
    
    var sessionIdFrame: [HandshakeExtensionTypes: Data]? {
        guard let streamId = streamId else { return nil }
        
        var streamIdData = Data(streamId.utf8)
        // Ensure the Stream ID does not exceed 512 bytes
        if streamIdData.count > 512 {
            streamIdData = streamIdData.prefix(512)
        }
        
        // Pad the data to the next multiple of 4 bytes
        let paddingLength = (4 - (streamIdData.count % 4)) % 4
        if paddingLength > 0 {
            streamIdData.append(contentsOf: [UInt8](repeating: 0, count: paddingLength))
        }
        
        return [.streamId: streamIdData]
    }
    
}
