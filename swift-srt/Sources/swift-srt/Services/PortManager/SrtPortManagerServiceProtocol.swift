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
    var sockets: AnyPublisher<[UdpHeader: [UInt32: SrtSocketProtocol]], Never> { get }
    var frames: AnyPublisher<(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data), Never> { get }

    func addListener(endpoint: IPv4Address, port: NWEndpoint.Port) -> Void
    func addConnection(header: UdpHeader, connection: SrtConnectionProtocol) -> Void
    func addSocket(header: UdpHeader, socket: SrtSocketProtocol) -> Void
    func addFrame(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data) -> Void
    
    func removeListener(port: NWEndpoint.Port) -> Void
    func removeConnection(header: UdpHeader) -> Void
    func removeSocket(header: UdpHeader, socketId: UInt32) -> Void

    func shutdown(port: NWEndpoint.Port?) -> Void
    
}
