//
//  PacketSenderProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
//

import Foundation

protocol PacketSenderProtocol {
    
    func send(packet: SrtPacket) -> Void
    
}
