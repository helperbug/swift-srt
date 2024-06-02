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
    let metrics: MetricsProtocol? = nil
    
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
        self.state.send(self, data)
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
        
    }
    
    private func handleData(socketId: UInt32, frame: Data) {
        
        guard let socket = self.sockets[socketId] else {
            print("this should never happen, it is an error")
            return
        }
        
        socket.onFrameReceived(frame)
        
    }
    
    func ipStringToData(ipString: String) -> Data? {
        let components = ipString.split(separator: ".")
        guard components.count == 4 else { return nil }

        let ipv4Bytes = components.compactMap { UInt8($0) }.reversed()
        guard ipv4Bytes.count == 4 else { return nil }

        let paddedBytes = ipv4Bytes + [UInt8](repeating: 0, count: 12)
        return Data(paddedBytes)
    }

    
    private func handleControl(packet: SrtPacket, synCookie: UInt32) {
        guard let controlPacket = ControlPacketFrame(packet.contents),
              let controlType = ControlTypes(rawValue: controlPacket.controlType) else {
            print("Invalid control packet")
            return
        }
        
        let socketId = packet.destinationSocketID
        
        var socketContext = SrtSocketContext(encrypted: true, id: socketId, onFrameReceived: { _ in},
                                             onHintsReceived: { _ in },
                                             onLogReceived: { _ in },
                                             onMetricsReceived: { _ in },
                                             onStateChanged: { _ in })
        
        switch controlType {
        case .handshake:
            guard let handshake = SrtHandshake(data: packet.contents) else {
                print("Invalid handshake packet")
                return
            }
            
            if let data = ipStringToData(ipString: updHeader.sourceIp) {
                print(data)
            }
            
            if handshake.isInductionRequest {

                sockets[handshake.srtSocketID] = socketContext

                let response = SrtHandshake.makeInductionResponse(
                    srtSocketID: handshake.srtSocketID,
                    initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
                    synCookie: self.updHeader.cookie,
                    peerIpAddress: ipStringToData(
                        ipString: updHeader.sourceIp
                    )!,
                    encrypted: false
                )

                let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: handshake.srtSocketID, contents: Data())

                let contents = response.makePacket(socketId: handshake.srtSocketID).contents

                send2(header: packet, contents: contents)
                
                
                print("Induction request processed, new socket added with ID \(handshake.srtSocketID)")
            } else if handshake.handshakeType == .conclusion {
                print("Handshake conclusion processed for socket \(handshake.srtSocketID)")
            }
        case .keepAlive:
            print("KeepAlive packet received")
        case .acknowledgement:
            print("Acknowledgement packet received")
        case .negativeAcknowledgement:
            print("Negative Acknowledgement packet received")
        case .congestionWarning:
            print("Congestion Warning packet received")
        case .shutdown:
            let socketId = controlPacket.destinationSocketID
            sockets.removeValue(forKey: socketId)
            if sockets.isEmpty {
                print("All sockets closed, cancelling connection")
                connection.cancel()
            } else {
                print("Socket \(socketId) shutdown, remaining sockets: \(sockets.count)")
            }
        case .ackack:
            print("ACKACK packet received")
        case .dropRequest:
            print("Drop Request packet received")
        case .peerError:
            print("Peer Error packet received")
        case .userDefined:
            print("User Defined packet received")
        case .none:
            print("None packet type received")
        }
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
    
    //    func send(srtPacket: SrtPacket) {
    //        guard let header = llrpMessage.header else {
    //            fatalError("Llrp request missing header")
    //        }
    //
    //
    //
    //        let message = NWProtocolFramer.Message(llrpHeader: header)
    //        let metadata = [message]
    //        let identifier = "\(self)"
    //
    //        print("Message type \(message.messageType)")
    //
    //        let content = srtPacket.data
    //        let context = NWConnection.ContentContext(identifier: identifier, metadata: metadata)
    //        // Send the application content along with the message.
    //        self.connection.send(content: content, contentContext: context, isComplete: true, completion: .idempotent)
    //    }
    
    func send2(header: SrtPacket, contents: Data) {
        let message = NWProtocolFramer.Message(srtPacket: header)
        let metadata = [message]
        let identifier = "\(self)"
        
        let context = NWConnection.ContentContext(identifier: identifier, metadata: metadata)
        self.connection.send(content: contents, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
