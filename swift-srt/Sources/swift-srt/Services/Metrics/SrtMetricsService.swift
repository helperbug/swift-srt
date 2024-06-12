//
//  SrtMetricsService.swift
//
//
//  Created by Ben Waidhofer on 6/11/24.
//

import Combine
import Foundation
import Network

public class SrtMetricsService: SrtMetricsServiceProtocol {
    
    public let icon: String = "⏱️"
    public let source: String = "Metrics"
    
    private var interval: TimeInterval
    private let logService: LogServiceProtocol

    private var listenerStore: [NWEndpoint.Port: SrtMetrics] = [:]
    private var connectionStore: [UdpHeader: SrtMetrics] = [:]
    private var socketStore: [SocketKey: SrtMetrics] = [:]
    private var frameStore: [FrameKey: SrtMetrics] = [:]

    @Published private var _listenerMetrics: (port: NWEndpoint.Port, receive: SrtMetricsModel, send: SrtMetricsModel)
    public var listenerMetrics: AnyPublisher<(port: NWEndpoint.Port, receive: SrtMetricsModel, send: SrtMetricsModel), Never> {

        $_listenerMetrics.eraseToAnyPublisher()

    }
    
    @Published private var _connectionMetrics: (header: UdpHeader, receive: SrtMetricsModel, send: SrtMetricsModel)
    public var connectionMetrics: AnyPublisher<(header: UdpHeader, receive: SrtMetricsModel, send: SrtMetricsModel), Never> {

        $_connectionMetrics.eraseToAnyPublisher()

    }
    
    @Published private var _socketMetrics: (header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel)
    public var socketMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> {
        
        $_socketMetrics.eraseToAnyPublisher()

    }
    
    @Published private var _frameMetrics: (header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel)
    public var frameMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> {
        
        $_frameMetrics.eraseToAnyPublisher()

    }

    public init(logService: LogServiceProtocol, interval: TimeInterval) {
        
        self.logService = logService
        self.interval = interval
        
        _listenerMetrics = (port: .any, receive: .blank, send: .blank)
        _connectionMetrics = (header: .blank, receive: .blank, send: .blank)
        _socketMetrics = (header: .blank, socketId: 0, receive: .blank, send: .blank)
        _frameMetrics = (header: .blank, socketId: 0, frameId: 0, receive: .blank, send: .blank)
        
    }
    
    public func storeListenerMetric(port: NWEndpoint.Port, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        self.listenerStore[port, default: .init()].delta(receive: receive, send: send)
        
    }

    public func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        self.connectionStore[header, default: .init()].delta(receive: receive, send: send)

    }
    
    public func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        let socketKey = SocketKey(header: header, socketId: socketId)
        self.socketStore[socketKey, default: .init()].delta(receive: receive, send: send)

    }
    
    public func storeFrameMetric(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        let frameKey = FrameKey(header: header, socketId: socketId, frameId: frameId)
        self.frameStore[frameKey, default: .init()].delta(receive: receive, send: send)

    }
    
    public func log(_ message: String) {
        
        logService.log(self.icon, self.source, message)

    }
    
    private struct SocketKey: Hashable {
        
        let header: UdpHeader
        let socketId: UInt32

        func hash(into hasher: inout Hasher) {
            hasher.combine(header)
            hasher.combine(socketId)
        }
        
    }
    
    private struct FrameKey: Hashable {
        
        let header: UdpHeader
        let socketId: UInt32
        let frameId: UInt32

        func hash(into hasher: inout Hasher) {

            hasher.combine(header)
            hasher.combine(socketId)
            hasher.combine(frameId)

        }
        
    }
}
