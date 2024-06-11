//
//  SrtPortManagerService.swift
//
//
//  Created by Ben Waidhofer on 6/9/24.
//

import Combine
import Foundation
import Network

public class SrtPortManagerService: SrtPortManagerProtocol {
    
    @Published private var _listeners: [NWEndpoint.Port: SrtPortListenerProtocol] = [:]
    @Published public var _connections: [UdpHeader: SrtConnectionProtocol] = [:]
    @Published public var _metrics: (UdpHeader, SrtMetricsModel) = (.blank, .blank)

    public init() {
        
    }
    
    public var listeners: AnyPublisher<[NWEndpoint.Port: SrtPortListenerProtocol], Never> {

        $_listeners.eraseToAnyPublisher()

    }
    
    public var connections: AnyPublisher<[UdpHeader: SrtConnectionProtocol], Never> {

        $_connections.eraseToAnyPublisher()

    }
    
    public var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> {

        $_metrics.eraseToAnyPublisher()

    }

    public func add(endpoint: IPv4Address, port: NWEndpoint.Port) {
        
        _listeners[port] = SrtPortListenerContext(
            endpoint: endpoint,
            port: port,
            onConnection: { connection in
                self._connections[connection.udpHeader] = connection
            },
            onConnectionRemove: { updHeader in
                self._connections[updHeader] = nil
            },
            onMetric: { (header, model) in
                self._metrics = (header, model)
            }
        )
        
    }
    
    public func shutdown() {
        
        _listeners.values.forEach { listener in
            
            listener.close()
            
        }
        
    }
    
}
