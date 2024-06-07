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

public class ConnectionContext: SrtConnectionProtocol {
    
    public var onCanceled: (UdpHeader) -> Void
    public var sockets: [UInt32: SrtSocketProtocol] = [:]
    var state: ConnectionState
    private var pendingListener: SrtListenerContext? = nil

    let udpHeader: UdpHeader
    let connection: NWConnection
    
    public var connectionState: ConnectionStates {
        state.name
    }

    public var key: String {
        "\(self.udpHeader.sourceIp):\(self.udpHeader.sourcePort)"
    }
    
    public required init(updHeader: UdpHeader,
                         connection: NWConnection,
                         onCanceled: @escaping (UdpHeader) -> Void) {
        
        self.connection = connection
        self.udpHeader = updHeader
        self.onCanceled = onCanceled
        
        state = ConnectionSetupState()
    }
    
    public func cancel() {
        if connectionState == .ready {
            connection.cancel()
            self.onCanceled(self.udpHeader)
        }
    }
    
    public func removeSocket(id: UInt32) {
        
        if let socket = sockets[id] {
            socket.shutdown()
        }
        
        sockets[id] = nil
        
    }
    
    public func start() {
        
        if self.state.name == .setup {
            state.auto(self)
        }
        
    }
    
    public func onStateChanged(_ state: NWConnection.State) {
        
        self.state.onStateChanged(self, state: state)
        
    }
    
    @discardableResult
    func set(newState: ConnectionStates) -> Self {
        
        self.state = newState.state
        
        return self
        
    }
    
}

extension ConnectionContext {
    
    func receive(packet: SrtPacket) {
        
        if packet.isData {
            self.handleData(socketId: packet.destinationSocketID, frame: packet.contents)
        } else {
            self.handleControl(packet: packet)
        }
        
    }
    
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
    
    static func make(serverIp: String,
                     serverPort: UInt16,
                     _ connection: NWConnection,
                     onCanceled: @escaping (String) -> Void
    ) -> ConnectionContext? {
        
        guard case .hostPort(let caller, let port) = connection.endpoint else {
            return nil
        }
        
        guard let host = caller as? NWEndpoint.Host else {
            return nil
        }
        
        guard case .ipv4(let ipv4Address) = host else {
            return nil
        }
        
        let updHeader: UdpHeader = .init(
            sourceIp: "\(ipv4Address)",
            sourcePort: port.rawValue,
            destinationIp: serverIp,
            destinationPort: serverPort
            )
        
        let context: ConnectionContext = .init(updHeader: updHeader, connection: connection) { key in
         
            
            
        }
        
        connection.stateUpdateHandler = context.onStateChanged(_ :)
        
        return context
        
    }
}

extension ConnectionContext: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(udpHeader)
    }
    
    public static func == (lhs: ConnectionContext, rhs: ConnectionContext) -> Bool {
        return lhs.udpHeader == rhs.udpHeader
    }
}

extension ConnectionContext { // handlers
    
    private func handleData(socketId: UInt32, frame: Data) {

        guard let defaultSocket = self.sockets.values.first else {
            fatalError()
        }
        
        guard let dataPacket = DataPacketFrame(frame) else {
            print("bad data")
            return
        }
        
        if let matchedSocket = self.sockets[socketId] {
            
            matchedSocket.handleData(packet: dataPacket)
            
        } else {
            
            defaultSocket.handleData(packet: dataPacket)
            
        }
        
        // socket.onFrameReceived(frame)
        
    }

    private func handleHandshake(handshake: SrtHandshake) {

        if let pendingListener {

            pendingListener.handleHandshake(handshake: handshake)

        } else {

            self.pendingListener = SrtListenerContext(
                srtSocketID:    handshake.srtSocketID,
                initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
                synCookie: self.udpHeader.cookie,
                peerIpAddress: self.udpHeader.sourceIp.ipStringToData!,
                encrypted: false,
                send: self.send(header:contents:),
                onSocketCreated: { socket in
                    self.sockets[socket.socketId] = socket
                    self.pendingListener = nil
                })
        }
        
    }
    
    private func handleControl(packet: SrtPacket) {
        
        guard let controlPacket = ControlPacketFrame(packet.contents),
              let controlType = ControlTypes(rawValue: controlPacket.controlType) else {
            print("Invalid control packet")
            return
        }
        
        let socketId = packet.destinationSocketID
        
        var socketContext = SrtSocketContext(encrypted: true,
                                             socketId: socketId,
                                             synCookie: self.udpHeader.cookie,
                                             onFrameReceived: { _ in},
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
            
            self.handleHandshake(handshake: handshake)
//            if let data = udpHeader.sourceIp.ipStringToData {
//                print(data)
//            }
//            
//            if handshake.isInductionRequest {
//                
//                var srtListener = SrtListenerContext(
//                    srtSocketID: handshake.srtSocketID,
//                    initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
//                    synCookie: self.udpHeader.cookie,
//                    peerIpAddress: self.udpHeader.sourceIp.ipStringToData!,
//                    encrypted: false,
//                    send: { _, _ in },
//                    onSocketCreated: { _ in }
//                )
//                
//
//                sockets[handshake.srtSocketID] = socketContext
//                
//                let response = SrtHandshake.makeInductionResponse(
//                    srtSocketID: handshake.srtSocketID,
//                    initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
//                    synCookie: self.udpHeader.cookie,
//                    peerIpAddress: self.udpHeader.sourceIp.ipStringToData!,
//                    encrypted: false
//                )
//                
//                let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: handshake.srtSocketID, contents: Data())
//                
//                let contents = response.makePacket(socketId: handshake.srtSocketID).contents
//                
//                send(header: packet, contents: contents)
//                
//            } else if handshake.handshakeType == .conclusion,
//                      let socket = sockets[handshake.srtSocketID],
//                      handshake.isConclusionRequest(synCookie: socket.synCookie) {
//                
//                let response = SrtHandshake.makeConclusionResponse(
//                    srtSocketID: handshake.srtSocketID,
//                    initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
//                    synCookie: self.udpHeader.cookie,
//                    peerIpAddress: self.udpHeader.sourceIp.ipStringToData!
//                )
//                
//                var payload: Data = .init()
//                
//                handshake.extensions.forEach { handshakeExt in
//                    socket.update(type: handshakeExt.key, data: handshakeExt.value)
//                }
//                
//                let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: handshake.srtSocketID, contents: Data())
//                
//                let contents = response.makePacket(socketId: handshake.srtSocketID).contents + (handshake.extensions.first(where: { $0.key == .streamId})?.value ?? Data())
//                
//                send(header: packet, contents: contents)
//                
//                print("Handshake conclusion processed for socket \(handshake.srtSocketID)")
//            }
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
    
    func send(header: SrtPacket, contents: Data) {
        let message = NWProtocolFramer.Message(srtPacket: header)
        let metadata = [message]
        let identifier = "\(self)"
        
        let context = NWConnection.ContentContext(identifier: identifier, metadata: metadata)
        self.connection.send(content: contents, contentContext: context, isComplete: true, completion: .idempotent)
    }
}
/*
 public class ConnectionContext2 {
 
 public var onCanceled: (String) -> Void
 
 public var onStateChanged: (Bool) -> Void
 
 public var ipAddress: IPv4Address
 
 public var port: NWEndpoint.Port
 
 public var onSocketCreated: (any SrtSocketProtocol) -> Void
 
 public var onSocketRemoved: (String) -> Void
 
 public func close() {
 
 }
 
 var connection: NWConnection
 let serverIp: String
 let serverPort: UInt16
 
 var sockets: [UInt32: SrtSocketProtocol] = [:]
 let metrics: MetricsProtocol? = nil
 
 var state: ConnectionState = ConnectionSetupState()
 
 public var connectionState: ConnectionStates {
 state.name
 }
 
 var key: String {
 "\(ipAddress.debugDescription):\(port)"
 }
 
 var updHeader: UdpHeader {
 UdpHeader(
 sourceIp: "\(ipAddress)",
 sourcePort: port.rawValue,
 destinationIp: serverIp,
 destinationPort: serverPort
 )
 }
 
 public init(
 serverIp: String,
 serverPort: UInt16,
 connection: NWConnection,
 ipAddress: IPv4Address,
 port: NWEndpoint.Port,
 onStateChanged: @escaping (Bool) -> (),
 onSocketCreated: @escaping (SrtSocketProtocol) -> (),
 onSocketRemoved: @escaping (String)-> ()
 ) {
 
 self.serverIp = serverIp
 self.serverPort = serverPort
 self.connection = connection
 self.ipAddress = ipAddress
 self.port = port
 self.onStateChanged = onStateChanged
 self.onSocketCreated = onSocketCreated
 self.onSocketRemoved = onSocketRemoved
 self.onCanceled = { _ in }
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
 onCanceled: @escaping (String) -> Void
 ) -> ConnectionContext? {
 
 guard case .hostPort(let caller, let port) = connection.endpoint else {
 return nil
 }
 
 guard let host = caller as? NWEndpoint.Host else {
 return nil
 }
 
 guard case .ipv4(let ipv4Address) = host else {
 return nil
 }
 
 let context: ConnectionContext = .init(
 serverIp: serverIp,
 serverPort: serverPort,
 connection: connection,
 ipAddress: ipv4Address,
 port: port
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
 
 private func handleControl(packet: SrtPacket, synCookie: UInt32) {
 guard let controlPacket = ControlPacketFrame(packet.contents),
 let controlType = ControlTypes(rawValue: controlPacket.controlType) else {
 print("Invalid control packet")
 return
 }
 
 let socketId = packet.destinationSocketID
 
 var socketContext = SrtSocketContext(encrypted: true,
 socketId: socketId,
 synCookie: synCookie,
 onFrameReceived: { _ in},
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
 } else if handshake.handshakeType == .conclusion,
 let socket = sockets[handshake.srtSocketID],
 handshake.isConclusionRequest(synCookie: socket.synCookie) {
 
 let response = SrtHandshake.makeConclusionResponse(
 srtSocketID: handshake.srtSocketID,
 initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
 synCookie: self.updHeader.cookie,
 peerIpAddress: ipStringToData(
 ipString: updHeader.sourceIp
 )!
 )
 
 var payload: Data = .init()
 
 handshake.extensions.forEach { handshakeExt in
 socket.update(type: handshakeExt.key, data: handshakeExt.value)
 }
 
 let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: handshake.srtSocketID, contents: Data())
 
 let contents = response.makePacket(socketId: handshake.srtSocketID).contents + (handshake.extensions.first(where: { $0.key == .streamId})?.value ?? Data())
 
 send2(header: packet, contents: contents)
 
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
 */
