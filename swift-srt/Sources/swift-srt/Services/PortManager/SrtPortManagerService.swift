//
//  SrtPortManagerService.swift
//
//
//  Created by Ben Waidhofer on 6/9/24.
//

import Combine
import Foundation
import Network

public class SrtPortManagerService: SrtPortManagerServiceProtocol {

    public var icon: String = "⚓️"
    public var source: String = "Port Manager"

    private let logService: LogServiceProtocol
    
    @Published private var _listeners: [NWEndpoint.Port: SrtPortListenerProtocol] = [:]
    @Published private var _connections: [UdpHeader: SrtConnectionProtocol] = [:]
    @Published private var _metrics: (UdpHeader, SrtMetricsModel) = (.blank, .blank)
    @Published private var _sockets: [UdpHeader : [UInt32 : any SrtConnectionProtocol]] = [:]

    public init(logService: LogServiceProtocol) {
        
        self.logService = logService
        
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

    public var sockets: AnyPublisher<[UdpHeader : [UInt32 : any SrtConnectionProtocol]], Never> {
        $_sockets.eraseToAnyPublisher()
    }

    
    public func log(_ message: String) {
        
        logService.log(self.icon, self.source, message)
        
    }
    
    public func addListener(endpoint: IPv4Address, port: NWEndpoint.Port) {
        
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
    
    public func shutdown(port: NWEndpoint.Port? = nil) {
        
        _listeners.values.forEach { listener in

            if let port,
               listener.port == port {
                listener.close()
            } else {
                listener.close()
            }
            
        }
        
    }
    
}
