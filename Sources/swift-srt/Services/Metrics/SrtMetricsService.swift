//
//  SrtMetricsService.swift
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

public class SrtMetricsService: SrtMetricsServiceProtocol {
    
    public let icon: String = "⏱️"
    public let source: String = "Metrics"
    
    private let logService: LogServiceProtocol
    private var timer: AnyCancellable? = nil
    private let metricsWorker: DispatchQueue = .init(label: "Metrics Worker", qos: .background)

    private var listenerStore: [NWEndpoint.Port: SrtMetrics] = [:]
    private var connectionStore: [UdpHeader: SrtMetrics] = [:]
    private var socketStore: [SocketKey: SrtMetrics] = [:]
    private var frameStore: [FrameKey: SrtMetrics] = [:]

    @Published private var _uptime: Int = 0
    public var uptime: AnyPublisher<Int, Never> {
        $_uptime.eraseToAnyPublisher()
    }
    
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
        
        _listenerMetrics = (port: .any, receive: .blank, send: .blank)
        _connectionMetrics = (header: .blank, receive: .blank, send: .blank)
        _socketMetrics = (header: .blank, socketId: 0, receive: .blank, send: .blank)
        _frameMetrics = (header: .blank, socketId: 0, frameId: 0, receive: .blank, send: .blank)
        
        self.timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in

                self.flushMetrics()

            }
    }
    
    public func storeListenerMetric(port: NWEndpoint.Port, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        metricsWorker.async {
            
            if let existing = self.listenerStore[port] {
                existing.delta(receive: receive, send: send)
            } else {
                var new = SrtMetrics()
                new.delta(receive: receive, send: send)
                self.listenerStore[port] = new
            }

        }
        
    }

    public func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        metricsWorker.async {
            
            if let existing = self.connectionStore[header] {
                existing.delta(receive: receive, send: send)
            } else {
                var new = SrtMetrics()
                new.delta(receive: receive, send: send)
                self.connectionStore[header] = new
            }
            
            self.storeListenerMetric(port: NWEndpoint.Port(integerLiteral: header.destinationPort), receive: receive, send: send)
            
        }

    }
    
    public func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        metricsWorker.async {
            
            let socketKey = SocketKey(header: header, socketId: socketId)
            
            if let existing = self.socketStore[socketKey] {
                existing.delta(receive: receive, send: send)
            } else {
                var new = SrtMetrics()
                new.delta(receive: receive, send: send)
                self.socketStore[socketKey] = new
            }
            
        }

    }
    
    public func storeFrameMetric(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
        metricsWorker.async {
            
            let frameKey = FrameKey(header: header, socketId: socketId, frameId: frameId)
            
            if let existing = self.frameStore[frameKey] {
                existing.delta(receive: receive, send: send)
            } else {
                var new = SrtMetrics()
                new.delta(receive: receive, send: send)
                self.frameStore[frameKey] = new
            }
            
        }

    }
    
    public func log(_ message: String) {
        
        logService.log(self.icon, self.source, message)

    }
    
    public func flushMetrics() {
        
        metricsWorker.async {
   
            self._uptime += 1

            usleep(1000)
            
            let listenerStore = self.listenerStore
            self.listenerStore = [:]
            
            let connectionStore = self.connectionStore
            self.connectionStore = [:]
            
            let socketStore = self.socketStore
            self.socketStore = [:]
            
            let frameStore = self.frameStore
            self.frameStore = [:]

            listenerStore.forEach { pair in
                
                let (receive, send) = pair.value.capture()
                self._listenerMetrics = (port: pair.key, receive: receive, send: send)
                
            }
            
            connectionStore.forEach { pair in
                
                let (receive, send) = pair.value.capture()
                self._connectionMetrics = (header: pair.key, receive: receive, send: send)

            }
            
            socketStore.forEach { pair in
                
                let (receive, send) = pair.value.capture()
                self._socketMetrics = (header: pair.key.header, socketId: pair.key.socketId, receive: receive, send: send)
                
            }
            
            frameStore.forEach { pair in
                
                let (receive, send) = pair.value.capture()
                self._socketMetrics = (header: pair.key.header, socketId: pair.key.socketId, receive: receive, send: send)
                
            }
            
        }

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
