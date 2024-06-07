//
//  HandshakeContext.swift
//
//
//  Created by Ben Waidhofer on 5/31/24.
//

import Foundation
import Network

public class HandshakeContext {
    
    private var _socketId: UInt32
    private var _initialPacketSequenceNumber: UInt32
    private var state: HandshakeState
    private var connection: NWConnection
    private var _synCookie: UInt32
    private var _peerIpAddress: Data
    
    public init(connection: NWConnection,
                peerIpAddress: Data,
                socketId: UInt32,
                initialPacketSequenceNumber: UInt32,
                synCookie: UInt32
    ) {

        self._socketId = socketId
        self._synCookie = synCookie
        self._initialPacketSequenceNumber = initialPacketSequenceNumber
        self._peerIpAddress = peerIpAddress
        self.connection = connection
        self.state = HandshakeWaitingState()

    }
    
    @discardableResult
    func set(newState: HandshakeStates) -> HandshakeState {

        self.state = newState.instance
        return self.state

    }
}

extension HandshakeContext: HandshakeProtocol {
    public func makeInductionRequest() -> SrtPacket {
        return .blank
    }
    
    public func makeInductionResponse() -> SrtPacket {
        return .blank
    }
    
    public func makeConclusionRequest() -> SrtPacket {
        return .blank
    }
    
    public func makeConclusionResponse() -> SrtPacket {
        return .blank
    }
    
    public func receive(packet: SrtPacket) {
        state.onPacketReceived(self, packet: packet)
    }
    
    public var name: HandshakeStates { self.state.name }
    public var socketId: UInt32 { self._socketId }
    public var initialPacketSequenceNumber: UInt32 { self._initialPacketSequenceNumber }
    public var synCookie: UInt32 { self._synCookie }
    public var peerIpAddress: Data { self._peerIpAddress }

    func onPacketReceived(packet: SrtPacket) {

        state.onPacketReceived(self, packet: packet)

    }

    public func send(data: Data) {
        
        connection.send(content: data, completion: .contentProcessed({ _ in }))
        
    }
    
}
