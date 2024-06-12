//
//  SrtPortManagerProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/9/24.
//

import Combine
import Foundation
import Network

public protocol SrtPortManagerServiceProtocol: ServiceProtocol {
    
    var listeners: AnyPublisher<[NWEndpoint.Port: SrtPortListenerProtocol], Never> { get }
    var connections: AnyPublisher<[UdpHeader: SrtConnectionProtocol], Never> { get }
    var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> { get }
    var sockets: AnyPublisher<[UdpHeader: [UInt32: SrtConnectionProtocol]], Never> { get }

    func addListener(endpoint: IPv4Address, port: NWEndpoint.Port) -> Void
    func shutdown(port: NWEndpoint.Port?) -> Void
    
}
