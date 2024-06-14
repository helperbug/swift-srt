//
//  SrtPacketSender.swift
//
//
//  Created by Ben Waidhofer on 6/12/24.
//

import Foundation

protocol SrtPacketSender {
    
    var send: (SrtPacket, Data) -> Void { get }
    
}
