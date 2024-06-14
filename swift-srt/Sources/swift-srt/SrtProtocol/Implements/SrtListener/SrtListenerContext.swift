//
//  SrtListenerContext.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
//

import Foundation

public class SrtListenerContext: SrtPacketSender {
    
    let srtSocketID: UInt32
    let initialPacketSequenceNumber: UInt32
    let synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool
    let send: (SrtPacket, Data) -> Void
    let onSocketCreated: (SrtSocketProtocol) -> Void

    private var state: SrtListenerState
    
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
        self.state = StrListenerInducedState()
        self.send = send
        self.onSocketCreated = onSocketCreated
        
        self.state.auto(self)
    }
    
    func handleHandshake(handshake: SrtHandshake) {
        
        self.state.handleHandshake(self, handshake: handshake)
        
    }
    
    @discardableResult
    func set(newState: SrtListenerStates) -> SrtListenerState {
        
        print("setting listener state to \(newState.label)")
        self.state = newState.instance
        return self.state
        
    }
    
}
