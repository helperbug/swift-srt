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

    var sockets: [UInt32: SrtSocketProtocol] = [:]
    
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
        if self.state.name == .setup {
            state.auto(self)
        }
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
            host: "\(caller.debugDescription)",
            portNumber: port.rawValue,
            remove: remove
        )

        connection.stateUpdateHandler = context.onStateChanged(_ :)

        return context
        
    }
    
    func receive(packet: SrtPacket) {
        
        if packet.isData {
            self.handleData(socketId: packet.destinationSocketID, frame: packet.contents)
        } else {
            self.handleControl(packet: packet, synCookie: updHeader.cookie)
        }
        
        if let handshake = SrtHandshake(data: packet.contents) {
            print("Handshake for SRT Socket \(handshake.srtSocketID), synCookie \(updHeader.cookie)")
        } else {
            print("Receiving packet \(packet)")
        }
    }
    
    private func handleData(socketId: UInt32, frame: Data) {
        
        guard let socket = self.sockets[socketId] else {
            print("this should never happen, it is an error")
            return
        }
        
        socket.onFrameReceived(frame)
        
    }
    
    private func handleControl(packet: SrtPacket, synCookie: UInt32) {

//        guard let controlPacket = ControlPacketFrame(packet: SrtPacket.contents) else {
//            print("this should never happen, it is an error")
//            return
//        }
//        
//        switch controlPacket.controlType {
//        case .handshake:
//            guard let handshake = SrtHandshake(data: data) else {
//                print("Invalid handshake packet")
//                return
//            }
//            if handshake.isInductionRequest {
//                let newSocket = SrtSocket(handshake: handshake, synCookie: synCookie)
//                sockets[newSocket.id] = newSocket
//                print("Induction request processed, new socket added with ID \(newSocket.id)")
//            } else if handshake.handshakeType == .conclusion {
//                print("Handshake conclusion processed for socket \(handshake.srtSocketID)")
//            }
//        case .shutdown:
//            let socketId = controlPacket.socketId
//            sockets.removeValue(forKey: socketId)
//            if sockets.isEmpty {
//                print("All sockets closed, cancelling connection")
//                connection.cancel()
//            } else {
//                print("Socket \(socketId) shutdown, remaining sockets: \(sockets.count)")
//            }
//        case .keepAlive:
//            print("KeepAlive packet received")
//        case .acknowledgement:
//            print("Acknowledgement packet received")
//        case .negativeAcknowledgement:
//            print("Negative Acknowledgement packet received")
//        case .congestionWarning:
//            print("Congestion Warning packet received")
//        case .peerError:
//            print("Peer Error packet received")
//        case .userDefined:
//            print("User Defined packet received")
//        case .serverDenial:
//            print("Server Denial packet received")
//        case .dataDropped:
//            print("Data Dropped packet received")
//        case .channelStatisticsRequest:
//            print("Channel Statistics Request packet received")
//        case .channelStatisticsResponse:
//            print("Channel Statistics Response packet received")
//        case .reserved:
//            print("Reserved packet type received")
//        }
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
