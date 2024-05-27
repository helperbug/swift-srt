//
//  SrtConnectionProtocol.swift
//
//
//  Created by Ben Waidhofer on 5/26/24.
//

import Foundation

protocol SrtConnectionProtocol {

    var onStateChanged: (Bool) -> Void { get }

    init(host: IPAddress, port: UInt16)
    func makeSocket(encrypted: Bool) -> SrtSocketProtocol
    func close() -> Void

}
