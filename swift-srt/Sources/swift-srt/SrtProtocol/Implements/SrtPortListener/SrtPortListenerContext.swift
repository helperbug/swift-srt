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
    
    private var _connections: CurrentValueSubject<[String: ConnectionContext], Never> = .init([:])
    private var _endpoint: IPv4Address
    private var _port: NWEndpoint.Port
    private var _listenerState: CurrentValueSubject<SrtPortListnerStates, Never> = .init(.none)
    private var onDataPacket: (DataPacketFrame) -> Void
    


    var listener: NWListener? = nil
    private var state: SrtPortListenerState

    public var contexts: [ConnectionContext] {
        connections.value.values.sorted(by: { $0.key < $1.key })
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
        logger: LoggerContext,
        onDataPacket: @escaping (DataPacketFrame) -> Void
    ) {
        self._endpoint = endpoint
        self._port = port
        self.state = SrtPortListenerNoneState()
        self.onDataPacket = onDataPacket

        logger.log(text: "Starting \(endpoint.debugDescription): \(port)")
        
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
        self._listenerState.send(newState.name)
        
        return newState
        
    }
    
}

extension SrtPortListenerContext {
    
    func newConnectionHandler(connection: NWConnection) {
        
        if let context = ConnectionContext.make(serverIp: _endpoint.debugDescription,
                                                serverPort: _port.rawValue,
                                                connection,
                                                onCanceled: onCanceled,
                                                onDataPackat: onDataPacket) {

            connections.value[context.key] = context
            context.start()
        }

    }
    
    func onCanceled(header: UdpHeader) {

        let key = "\(header.sourceIp):\(header.sourcePort)"
        
        _connections.value[key] = nil

    }

    func onStateChanged(_ state: NWListener.State) {

        self.state.onStateChanged(self, state: state)

    }
    
}

extension SrtPortListenerContext: SrtPortListener {

    public var listenerState: CurrentValueSubject<SrtPortListnerStates, Never> {

        _listenerState

    }
    
    public var connections: CurrentValueSubject<[String: ConnectionContext], Never> {

        _connections

    }
    
    public func close() {

        if self.state.name == .ready {

            _connections.value.values.forEach { connection in

                DispatchQueue.global(qos: .userInteractive).async {

                    connection.cancel()

                }
                
            }
            
            _connections.send([:])
            
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
