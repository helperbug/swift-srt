import Foundation

public class SrtCallerContext: SrtPacketSender {
    
    let srtSocketID: UInt32
    let initialPacketSequenceNumber: UInt32
    var synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool
    let send: (SrtPacket, Data) -> Void
    let onSocketCreated: (SrtSocketProtocol) -> Void

    private var state: SrtCallerState
    
    init(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        send: @escaping (SrtPacket, Data) -> Void,
        onSocketCreated: @escaping (SrtSocketProtocol) -> Void
    ) {

        self.srtSocketID = srtSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self.state = StrCallerStartState()
        self.send = send
        self.onSocketCreated = onSocketCreated
        
        self.state.auto(self)
        
    }
    
    func handleHandshake(handshake: SrtHandshake) {
        
        self.state.handleHandshake(self, handshake: handshake)
        
    }
    
    @discardableResult
    func set(newState: SrtCallerStates) -> SrtCallerState {
        
        print("setting caller state to \(newState.label)")
        self.state = newState.instance
        return self.state
        
    }
    
}
