//
//  ListenerContext.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/1/2024.
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

public class SrtPortListenerContext {
    
    @Published private var _connections: [UdpHeader: SrtConnectionProtocol] = [:]
    private var _endpoint: IPv4Address
    private var _port: NWEndpoint.Port
    @Published private var _listenerState: SrtPortListnerStates = .none
    @Published private var _metrics: (UdpHeader, SrtMetricsModel) = (UdpHeader.blank, SrtMetricsModel.blank)
    
    private let onConnection: (SrtConnectionProtocol) -> Void
    private let onConnectionRemove: (UdpHeader) -> Void
    private let onMetric: (UdpHeader, SrtMetricsModel) -> Void

    var listener: NWListener? = nil
    private var state: SrtPortListenerState

    public var contexts: [SrtConnectionProtocol] {
        _connections.values.sorted(by: { $0.udpHeader.sourcePort < $1.udpHeader.sourcePort })
    }
    
    var parameters: NWParameters {
        
        let srtProtocol = NWProtocolFramer.Options(definition: SrtProtocolFramer.definition)
        let udpOptions = NWProtocolUDP.Options()
        
        let parameters = NWParameters(dtls: nil, udp: udpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(srtProtocol, at: 0)
        
        return parameters
        
    }
    
    public init(
        endpoint: IPv4Address,
        port: NWEndpoint.Port,
        onConnection: @escaping (SrtConnectionProtocol) -> Void,
        onConnectionRemove: @escaping (UdpHeader) -> Void,
        onMetric: @escaping (UdpHeader, SrtMetricsModel) -> Void
    ) {
        
        self._endpoint = endpoint
        self._port = port
        self.onConnection = onConnection
        self.onConnectionRemove = onConnectionRemove
        self.onMetric = onMetric
        self.state = SrtPortListenerNoneState()

        // logger.log(text: "Starting \(endpoint.debugDescription): \(port)")
        
        self.state.auto(self)

    }
    
    @discardableResult
    func set(state: SrtPortListnerStates) -> SrtPortListenerState {
        
        let newState: SrtPortListenerState
        
        if state == .ready {
            
            newState = SrtPortListenerReadyState()

        } else {
            
            newState = SrtPortListenerNoneState()

        }
        
        self.state = newState
        self._listenerState = newState.name
        
        return newState
        
    }
    
}

extension SrtPortListenerContext {
    
    func newConnectionHandler(connection: NWConnection) {
        
        if let context = ConnectionContext.make(serverIp: _endpoint.debugDescription,
                                                serverPort: _port.rawValue,
                                                connection,
                                                onCanceled: onCanceled,
                                                onDataPackat: onDataPackat) {

            _connections[context.udpHeader] = context
            context.start()
            
            self.onConnection(context)
        }

    }
    
    func onCanceled(header: UdpHeader) {

        self._connections[header] = nil
        self.onConnectionRemove(header)

    }

    func onDataPackat(packet: DataPacketFrame) {

        let metric: SrtMetricsModel = .init(
            ackAckCount: 0,
            ackCount: 0,
            bytesCount: packet.data.count,
            controlCount: 0,
            dataPacketCount: 0,
            jitter: 0,
            latency: 0,
            nackCount: 0,
            roundTripTime: 0
        )

        if let entry = _connections.first {

            self.onMetric(entry.key, metric)

        }
        
    }

    func onStateChanged(_ state: NWListener.State) {

        self.state.onStateChanged(self, state: state)

    }
    
}

extension SrtPortListenerContext: SrtPortListenerProtocol {

    public var listenerState: AnyPublisher<SrtPortListnerStates, Never> {

        $_listenerState.eraseToAnyPublisher()

    }
    
    public var connections: AnyPublisher<[UdpHeader: SrtConnectionProtocol], Never> {

        $_connections.eraseToAnyPublisher()

    }
    
    public var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> {
        
        $_metrics.eraseToAnyPublisher()
        
    }
    
    public func close() {

        if self.state.name == .ready {

            _connections.values.forEach { connection in

                DispatchQueue.global(qos: .userInteractive).async {

                    connection.cancel()

                }
                
            }
            
            _connections = [:]
            
            if let listener {
                
                listener.cancel()
                
            }

        }

    }
    
    
    public var endpoint: IPv4Address {

        _endpoint

    }
    
    public var port: NWEndpoint.Port {

        _port

    }
    
}
