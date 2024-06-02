import Foundation

public class SrtSocketContext: SrtSocketProtocol {

    public let encrypted: Bool
    public let id: UInt32
    
    public var onFrameReceived: (Data) -> Void
    public var onHintsReceived: ([SrtSocketHints]) -> Void
    public var onLogReceived: (String) -> Void
    public var onMetricsReceived: ([SrtSocketMetrics]) -> Void
    public var onStateChanged: (SrtSocketStates) -> Void
    
    public init(encrypted: Bool,
                id: UInt32,
                onFrameReceived: @escaping (Data) -> Void,
                onHintsReceived: @escaping ([SrtSocketHints]) -> Void,
                onLogReceived: @escaping (String) -> Void,
                onMetricsReceived: @escaping ([SrtSocketMetrics]) -> Void,
                onStateChanged: @escaping (SrtSocketStates) -> Void) {
        
        self.encrypted = encrypted
        self.id = id
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
}
