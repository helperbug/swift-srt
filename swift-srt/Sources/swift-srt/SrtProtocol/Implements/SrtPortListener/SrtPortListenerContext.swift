//
//  ListenerContext.swift
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

public class SrtPortListenerContext {
    
    private var _endpoint: IPv4Address
    private var _port: NWEndpoint.Port
    @Published private var _listenerState: SrtPortListnerStates = .none
    @Published private var _metrics: (UdpHeader, SrtMetricsModel) = (UdpHeader.blank, SrtMetricsModel.blank)
    
    var listener: NWListener? = nil
    private var state: SrtPortListenerState
    private let logService: LogServiceProtocol
    private let managerService: SrtPortManagerServiceProtocol
    private let metricsService: SrtMetricsServiceProtocol

    public static var parameters: NWParameters {
        
        let srtProtocol = NWProtocolFramer.Options(definition: SrtProtocolFramer.definition)
        let udpOptions = NWProtocolUDP.Options()
        
        let parameters = NWParameters(dtls: nil, udp: udpOptions)
        parameters.defaultProtocolStack.applicationProtocols.insert(srtProtocol, at: 0)
        
        return parameters
        
    }
    
    public init(
        endpoint: IPv4Address,
        port: NWEndpoint.Port,
        logService: LogServiceProtocol,
        managerService: SrtPortManagerServiceProtocol,
        metricsService: SrtMetricsServiceProtocol
    ) {
        
        self._endpoint = endpoint
        self._port = port
        self.logService = logService
        self.managerService = managerService
        self.metricsService = metricsService
        self.state = SrtPortListenerNoneState()

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
                                                logService: logService,
                                                managerService: managerService,
                                                metricsService: metricsService) {

            context.start()

            managerService.addConnection(header: context.udpHeader, connection: context)
            
        }

    }
    
    func onCanceled(header: UdpHeader) {

        managerService.removeConnection(header: header)

    }

    func onStateChanged(_ state: NWListener.State) {

        self.state.onStateChanged(self, state: state)

    }
    
}

extension SrtPortListenerContext: SrtPortListenerProtocol {

    public var endpoint: IPv4Address {

        _endpoint

    }
    
    public var port: NWEndpoint.Port {

        _port

    }

    public var listenerState: AnyPublisher<SrtPortListnerStates, Never> {

        $_listenerState.eraseToAnyPublisher()

    }
    
    public var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> {
        
        $_metrics.eraseToAnyPublisher()
        
    }
    
    public func close() {

        if self.state.name == .ready {

            // self.state.primary(self)
            
            if let listener {
                listener.cancel()
            }

        }

    }
    
}
