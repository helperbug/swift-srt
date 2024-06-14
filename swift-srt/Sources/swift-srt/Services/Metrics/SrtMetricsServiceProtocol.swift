//
//  SrtMetricsServiceProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/11/24.
//

import Combine
import Foundation
import Network

public protocol SrtMetricsServiceProtocol: ServiceProtocol {
    
    var uptime: AnyPublisher<Int, Never> { get }
    var listenerMetrics: AnyPublisher<(port: NWEndpoint.Port, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var connectionMetrics: AnyPublisher<(header: UdpHeader, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var socketMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var frameMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }

    func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void
    func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void
    func storeFrameMetric(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void

}
