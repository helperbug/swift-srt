//
//  SrtPortManagerService.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  Portions of this project are based on the SRT protocol specification.
//  SRT is licensed under the Mozilla Public License, v. 2.0.
//  You may obtain a copy of the License at
//  https://github.com/Haivision/srt/blob/master/LICENSE
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import Network

public class SrtPortManagerService: SrtPortManagerServiceProtocol {
    
    public var icon: String = "⚓️"
    public var source: String = "Port Manager"
    
    private let logService: LogServiceProtocol
    private let metricsService: SrtMetricsServiceProtocol
    
    public init(logService: LogServiceProtocol, metricsService: SrtMetricsServiceProtocol) {
        
        self.logService = logService
        self.metricsService = metricsService
        
        self._frames = (header: .blank, socketId: 0, messageId: 0, frame: Data())
    }
    
    @Published private var _listeners: [NWEndpoint.Port: SrtPortListenerProtocol] = [:]
    public var listeners: AnyPublisher<[NWEndpoint.Port: SrtPortListenerProtocol], Never> {
        
        $_listeners.eraseToAnyPublisher()
        
    }
    
    @Published private var _connections: [UdpHeader: SrtConnectionProtocol] = [:]
    public var connections: AnyPublisher<[UdpHeader: SrtConnectionProtocol], Never> {
        
        $_connections.eraseToAnyPublisher()
        
    }
    
    @Published private var _metrics: (UdpHeader, SrtMetricsModel) = (.blank, .blank)
    public var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> {
        
        $_metrics.eraseToAnyPublisher()
        
    }
    
    @Published private var _sockets: [UdpHeader : [UInt32 : SrtSocketProtocol]] = [:]
    public var sockets: AnyPublisher<[UdpHeader : [UInt32 : SrtSocketProtocol]], Never> {
        $_sockets.eraseToAnyPublisher()
    }
    
    @Published private var _frames: (header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data)
    public var frames: AnyPublisher<(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data), Never> {
        $_frames.eraseToAnyPublisher()
    }
    
    
    public func log(_ message: String) {
        
        logService.log(self.icon, self.source, message)
        
    }
    
    public func addListener(endpoint: IPv4Address, port: NWEndpoint.Port) {
        
        _listeners[port] = SrtPortListenerContext(
            endpoint: endpoint,
            port: port,
            logService: logService,
            managerService: self,
            metricsService: metricsService
        )
        
    }
    
    public func addConnection(header: UdpHeader, connection: SrtConnectionProtocol) {
        
        _connections[header] = connection
        
    }
    
    public func addSocket(header: UdpHeader, socket: SrtSocketProtocol) {
        
        _sockets[header] = [socket.socketId: socket]
        
    }
    
    public func addFrame(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data) {
        
        _frames = (header: header, socketId: socketId, messageId: messageId, frame: frame)
        
    }
    
    public func removeListener(port: NWEndpoint.Port) {
        
        if let listener = _listeners[port] {
            
            var headers: [UdpHeader] = []
            
            _connections.forEach { connection in
                if connection.key.destinationPort == port.rawValue {
                    headers.append(connection.key)
                }
            }
            
            headers.forEach { header in
                removeConnection(header: header)
            }
            
            listener.close()
            _listeners[port] = nil
        }
        
    }
    
    public func removeConnection(header: UdpHeader) {
        
        if let connection = _connections[header] {
            _connections[header] = nil
            connection.cancel()
        }
        
    }
    
    public func removeSocket(header: UdpHeader, socketId: UInt32) {
        
        _sockets[header]?[socketId] = nil
        
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
    
    public func shutdownConnection(connection: UdpHeader) {

        if let connection = _connections[connection] {

            connection.shutdown()
            
        }

    }

}
