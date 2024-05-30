//
//  ConnectionContext.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 5/25/2024.
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

import Foundation
import Network

public class ConnectionContext {

    var connection: NWConnection
    let serverIp: String
    let serverPort: UInt16
    let host: String
    let portNumber: UInt16

    var sockets: [Int: SrtSocketProtocol] = [:]
    
    var remove: (String) -> Void
    var state: ConnectionState = ConnectionSetupState()
    
    public var connectionState: ConnectionStates {
        state.name
    }

    var key: String {
        "\(host):\(portNumber)"
    }

    var updHeader: UdpHeader {
        UdpHeader(
            sourceIp: host,
            sourcePort: portNumber,
            destinationIp: serverIp,
            destinationPort: serverPort
        )
    }
    
    public init(
        serverIp: String,
        serverPort: UInt16,
        connection: NWConnection,
        host: String,
        portNumber: UInt16,
        remove: @escaping (String)->()
    ) {
       
        self.serverIp = serverIp
        self.serverPort = serverPort
        self.connection = connection
        self.host = host
        self.portNumber = portNumber
        self.remove = remove

    }
    
    func start() {
        connection.start(queue: .global(qos: .utility))
        state.auto(self)
    }
    
    func onStateChanged(_ state: NWConnection.State) {

        print("State Changed: \(state)")
        self.state.onStateChanged(self, state: state)

    }
    
    func send(data: Data) {
        self.state.send(self.connection, data)
    }
    
    static func make(serverIp: String,
                     serverPort: UInt16,
                     _ connection: NWConnection,
                     remove: @escaping (String)->()
                ) -> ConnectionContext? {
        
        guard case .hostPort(let caller, let port) = connection.endpoint else {
            return nil
        }

        let context: ConnectionContext = .init(
            serverIp: serverIp,
            serverPort: serverPort,
            connection: connection,
            host: "\(caller)",
            portNumber: port.rawValue,
            remove: remove
        )

        connection.stateUpdateHandler = context.onStateChanged(_ :)

        return context
        
    }
    
    func receive(packet: SrtPacket) {
        print("Receiving packet \(packet)")
    }
    
    func shutdown(message: String) {
        
    }
    
    @discardableResult
    func set(newState: ConnectionStates) -> Self {

        self.state = newState.state

        return self

    }
    
}

extension ConnectionContext: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(serverIp)
        hasher.combine(serverPort)
        hasher.combine(host)
        hasher.combine(portNumber)
    }

    public static func == (lhs: ConnectionContext, rhs: ConnectionContext) -> Bool {
        return lhs.serverIp == rhs.serverIp && lhs.serverPort == rhs.serverPort && lhs.host == rhs.host && lhs.portNumber == rhs.portNumber
    }
}

extension ConnectionContext {
    
    func receiveNextMessage() {
        self.connection.receiveMessage { (data, context, isComplete, error) in
 
            /// first check for errors
            if let error {
                /// deal with error
                print(error)
                return
            }
            
            /// make sure there is a context
            guard let context else {
                // Should never happen
                print("no context")
                return
            }
            
            /// make sure the incoming message can be framed srt
            let srtFramer = context.protocolMetadata(definition: SrtProtocolFramer.definition)
            guard let srtFrame = srtFramer as? NWProtocolFramer.Message else {
                print("network protocol framer could not downcast SRT message")
                return
            }
           
            /// make sure there is data
            guard data != nil else {
                // Should never happen
                self.receiveNextMessage()
                return
            }
            
            guard let srtPacket = srtFrame.srtPacket else {
                // Should never happen
                self.receiveNextMessage()
                return
            }
            
            self.receive(packet: srtPacket)

            // on to the next message
            self.receiveNextMessage()
            
        }
    }
    
}
