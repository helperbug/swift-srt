import Foundation

public class SrtSocketContext: SrtSocketProtocol {
    
    public var id: UUID = .init()
    public var socketId: UInt32

    private var acknowledgementNumber: UInt32 = 0
    private var availableBufferSize: UInt32 = 8000
    private let initialTimestamp: TimeInterval
    private var packetsReceivingRate: UInt32 = 30000
    private var estimatedLinkCapacity: UInt32 = 1000
    private var lastAcknowledgedPacketSequenceNumber: UInt32 = 0
    private var receivingRate: UInt32 = 1024 * 1024
    private let rootTime: TimeInterval
    private var rtt: UInt32 = 100000
    private var rttVariance: UInt32 = 50000
    private var acks: [UInt32: UInt32] = [:]
    private let rttVarianceCalc: RttVariance = .init(maxSize: 10)

    init(encrypted: Bool,
         socketId: UInt32,
         synCookie: UInt32,
         dataPacket: DataPacketFrame = .blank) {
        
        self.id = UUID()
        self.encrypted = encrypted
        self.socketId = socketId
        self.synCookie = synCookie
        self.rootTime = Date().timeIntervalSince1970
        self.initialTimestamp = TimeInterval(dataPacket.timestamp)
        
    }

    var currentOffset: UInt32 {
        
        let currentTime = Date().timeIntervalSince1970
        let timeSinceRoot = currentTime - rootTime
        let biasedTimestamp = initialTimestamp + timeSinceRoot
        let offset = currentTime - biasedTimestamp

        return UInt32(offset * 1_000_000) // Convert to microseconds

    }
    
    var dataCount = 1
    
    public func handleData(packet: DataPacketFrame) -> AcknowledgementFrame?  {

        dataCount += 1
        
        guard dataCount % 20 == 0 else {
            return nil
        }

        acknowledgementNumber += 1
        lastAcknowledgedPacketSequenceNumber = packet.packetSequenceNumber

        print("lastAcknowledgedPacketSequenceNumber \(lastAcknowledgedPacketSequenceNumber)")
        
        let ackFrame = AcknowledgementFrame(isControl: true,
                                            controlType: .acknowledgement,
                                            reserved: 0,
                                            acknowledgementNumber: acknowledgementNumber,
                                            timestamp: currentOffset,
                                            destinationSocketID: socketId,
                                            lastAcknowledgedPacketSequenceNumber: lastAcknowledgedPacketSequenceNumber + 1,
                                            rtt: rtt,
                                            rttVariance: rttVariance,
                                            availableBufferSize: availableBufferSize,
                                            packetsReceivingRate: packetsReceivingRate,
                                            estimatedLinkCapacity: estimatedLinkCapacity,
                                            receivingRate: receivingRate)
        
        return ackFrame

    }
    
    public func shutdown() {
        
    }
    
    
    public func handleControl(controlPacket: SrtPacket) -> Result<SrtPacket, SocketError> {
        
        return .failure(.none)
        
    }
    
    public func handleAck(packet: AcknowledgementFrame)  {

        
        
    }
    
    public func handleAckAck(ackAck: AckAckFrame) {

        guard let sendTime = acks[ackAck.acknowledgementNumber]  else {
            print("Error \(ackAck.acknowledgementNumber) was not find")
            return
        }
        
        rtt = ackAck.timestamp - sendTime
        rttVariance = rttVarianceCalc.addSample(rtt)
            
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

    public let synCookie: UInt32
    
//    public var onFrameReceived: (Data) -> Void
//    public var onHintsReceived: ([SrtSocketHints]) -> Void
//    public var onLogReceived: (String) -> Void
//    public var onMetricsReceived: ([SrtSocketMetrics]) -> Void
//    public var onStateChanged: (SrtSocketStates) -> Void
    
//    public init(encrypted: Bool,
//                socketId: UInt32,
//                synCookie: UInt32,
//                onFrameReceived: @escaping (Data) -> Void,
//                onHintsReceived: @escaping ([SrtSocketHints]) -> Void,
//                onLogReceived: @escaping (String) -> Void,
//                onMetricsReceived: @escaping ([SrtSocketMetrics]) -> Void,
//                onStateChanged: @escaping (SrtSocketStates) -> Void) {
//        
//        self.id = UUID()
//        self.encrypted = encrypted
//        self.socketId = socketId
//        self.synCookie = synCookie
//        self.onFrameReceived = onFrameReceived
//        self.onHintsReceived = onHintsReceived
//        self.onLogReceived = onLogReceived
//        self.onMetricsReceived = onMetricsReceived
//        self.onStateChanged = onStateChanged
//    }
    
    public func sendFrame(data: Data) {
        // Implementation for sending data
        // onLogReceived("Sending frame with data size: \(data.count) bytes")
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
            print("stream Id: \(data.asString ?? "")")
            
            if let streamId = data.asString {
                // Trim the null terminator from the string if it exists
                if let nullIndex = streamId.firstIndex(of: "\0") {
                    let trimmedStreamId = String(streamId[..<nullIndex])
                    self.streamId = trimmedStreamId
                    print("trimmed stream Id: \(trimmedStreamId)")
                } else {
                    self.streamId = streamId
                }
            } else {
                print("empty stream Id")
            }
            
        default:
            break
        }
        
    }
    
    private class RttVariance {
        private var elements: [UInt32] = []
        private let maxSize: Int

        init(maxSize: Int) {
            self.maxSize = maxSize
        }

        func addSample(_ sample: UInt32) -> UInt32 {
            elements.append(sample)
            if elements.count > maxSize {
                elements.removeFirst()
            }
            return calculateVariance()
        }

        private func calculateVariance() -> UInt32 {
            let count = UInt32(elements.count)
            guard count > 1 else { return 0 }

            let mean = elements.reduce(0, +) / count
            let varianceSum: UInt32 = elements.reduce(0) { result, value in
                let diff = value > mean ? value - mean : mean - value
                return result + diff * diff
            }

            return varianceSum / (count - 1)
        }

        func allSamples() -> [UInt32] {
            return elements
        }
    }

}
