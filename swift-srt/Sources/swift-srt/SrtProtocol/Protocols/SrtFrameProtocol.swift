//
//  SrtFrameProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/5/24.
//

import Foundation

protocol SrtFrameProtocol {
    
    var packets: [Int: Data] { get }
    
}
