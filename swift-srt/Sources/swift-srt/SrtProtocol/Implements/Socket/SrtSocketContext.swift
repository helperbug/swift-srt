import Foundation

public class SrtSocketContext: SrtSocketProtocol {
    public func handleControl(controlPacket: SrtPacket) -> Result<SrtPacket, SocketError> {
        return .failure(.none)
    }
    
    
    public var filterControlType: UInt32? = nil
    
    public var filterControlInfo: Data? = nil
    
    public var groupId: UInt32? = 0
    
    public var groupType: UInt8? = 0
    
    public var groupFlags: UInt8? = 0
    
    public var groupWeight: UInt16? = 0
    
    public var filterControlFrame: [HandshakeExtensionTypes : Data]?
    
    public var groupControlFrame: [HandshakeExtensionTypes : Data]?
    
    
    public var srtVersion: UInt32? = nil
    
    public var srtFlags: UInt32? = nil
    
    public var receiverTsbpdDelay: UInt16? = nil
    
    public var senderTsbpdDelay: UInt16? = nil
    
    public var keyMaterialVersion: UInt32? = nil
    
    public var keyMaterialEncryptionType: UInt32? = nil
    
    public var keyMaterialKeyLength: UInt16? = nil
    
    public var keyMaterialWrapType: UInt16? = nil
    
    public var keyMaterialEncryptedKey: Data? = nil
    
    public var streamId: String? = nil
    
    public var initialPacketSequenceNumber: UInt32? = nil
    
    public var maximumTransmissionUnitSize: UInt32? = nil
    
    public var maximumFlowWindowSize: UInt32? = nil
    
    public var srtSocketID: UInt32? = nil
    
    
    public let encrypted: Bool
    public let id: UInt32
    public let synCookie: UInt32
    
    public var onFrameReceived: (Data) -> Void
    public var onHintsReceived: ([SrtSocketHints]) -> Void
    public var onLogReceived: (String) -> Void
    public var onMetricsReceived: ([SrtSocketMetrics]) -> Void
    public var onStateChanged: (SrtSocketStates) -> Void
    
    public init(encrypted: Bool,
                id: UInt32,
                synCookie: UInt32,
                onFrameReceived: @escaping (Data) -> Void,
                onHintsReceived: @escaping ([SrtSocketHints]) -> Void,
                onLogReceived: @escaping (String) -> Void,
                onMetricsReceived: @escaping ([SrtSocketMetrics]) -> Void,
                onStateChanged: @escaping (SrtSocketStates) -> Void) {
        
        self.encrypted = encrypted
        self.id = id
        self.synCookie = synCookie
        self.onFrameReceived = onFrameReceived
        self.onHintsReceived = onHintsReceived
        self.onLogReceived = onLogReceived
        self.onMetricsReceived = onMetricsReceived
        self.onStateChanged = onStateChanged
    }
    
    public func sendFrame(data: Data) {
        // Implementation for sending data
        onLogReceived("Sending frame with data size: \(data.count) bytes")
        // Logic to decompose the frame into packets and track with ACKs and NACKs
    }
    
    public func update(type: HandshakeExtensionTypes, data: Data) {
        
        print("updating \(type) with \(data.asString)")
        
        switch type {
            
        case .groupControl:
            if let groupMembershipFrame = GroupMembershipExtensionFrame(data) {
                self.groupId = groupMembershipFrame.groupId
                self.groupType = groupMembershipFrame.type
                self.groupFlags = groupMembershipFrame.flags
                self.groupWeight = groupMembershipFrame.weight
            }
            
        case .streamId:
            if let streamId = data.asString {
                self.streamId = streamId
                print("stream Id: \(streamId)")
            } else {
                print("empty stream Id")
            }

        default:
            break
        }
        
    }
    
}
