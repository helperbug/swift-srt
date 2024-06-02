//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 5/31/24.
//

import Foundation

protocol MetricsProtocol {
    
    func send(socket: SrtSocketProtocol, frame: Data, data: Data, timestamp: Date, sequenceNumber: UInt32, packetSize: Int, acknowledgmentInfo: String)
    
}
