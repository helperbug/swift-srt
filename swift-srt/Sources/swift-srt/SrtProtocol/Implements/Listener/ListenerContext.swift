//
//  ListenerContext.swift
//
//
//  Created by Ben Waidhofer on 4/30/24.
//

import Combine
import Foundation
import Network

public class ListenerContext {
    
    private var _connections: CurrentValueSubject<[String: ConnectionContext], Never> = .init([:])
    private var _endpoint: IPv4Address
    private var _port: NWEndpoint.Port
    private var _listenerState: CurrentValueSubject<ListenerStates, Never> = .init(.none)

    var listener: NWListener? = nil
    private var state: ListenerState

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
    
    public init(endpoint: IPv4Address, port: NWEndpoint.Port) {
        self._endpoint = endpoint
        self._port = port
        self.state = ListenerNoneState()
        self.state.auto(self)
        
    }
    
    @discardableResult
    func set(state: ListenerStates) -> ListenerState {
        
        let newState: ListenerState
        
        if state == .ready {
            
            newState = ListenerReadyState()

        } else {
            
            newState = ListenerNoneState()

        }
        
        self.state = newState
        
        return newState
        
    }
    
}

extension ListenerContext {
    
    func newConnectionHandler(connection: NWConnection) {
        
        if let context = ConnectionContext.make(serverIp: _endpoint.debugDescription,
                                                serverPort: _port.rawValue,
                                                connection,
                                                remove: remove) {

            connections.value[context.key] = context
            context.start()

        }

    }
    
    func remove(key: String) {

        _connections.value[key] = nil

    }

    func onStateChanged(_ state: NWListener.State) {

        switch state {

        case .ready:

            print("Listener is ready and accepting connections.")

        case .failed(let error):

            print("Listener failed with error: \(error)")

        case .waiting(let error):

            print("Listener is waiting to retry due to error: \(error)")

        case .cancelled:

            print("Listener has been cancelled.")

        default:

            break

        }
    }
    
}

extension ListenerContext: SrtListenerProtocol {

    public var listenerState: CurrentValueSubject<ListenerStates, Never> {

        _listenerState

    }
    
    public var connections: CurrentValueSubject<[String: ConnectionContext], Never> {

        _connections

    }
    
    public func close() {

        if self.state.name == .ready {

            _connections.value.values.forEach { connection in

                DispatchQueue.global(qos: .userInteractive).async {

                    connection.shutdown(message: "Endpoint closing")

                }
                
            }
            
            self.state.primary(self)

        }

    }
    
    
    public var endpoint: IPv4Address {

        _endpoint

    }
    
    public var port: NWEndpoint.Port {

        _port

    }
    
}
