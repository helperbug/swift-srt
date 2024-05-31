//
//  HandshakeProtocol.swift
//
//
//  Created by Ben Waidhofer on 5/30/24.
//

import Foundation

public protocol HandshakeProtocol {
    
    var name: HandshakeStates { get }
    var socketId: UInt32 { get }
    var synCookie: UInt32 { get }
    var peerIpAddress: Data { get }

    func receive(packet: SrtPacket) -> Void
    func send(data: Data) -> Void
    
}
