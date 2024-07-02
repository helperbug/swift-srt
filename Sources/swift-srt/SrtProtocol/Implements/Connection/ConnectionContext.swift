//
//  ConnectionContext.swift
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

/// Represent an active UPD connection with the SRT framer. A caller creates the connection context as soon as it connects. A listener
/// can create multiple connections, one for each connected client.
public class ConnectionContext: SrtConnectionProtocol {
    
    public var sockets: [UInt32: SrtSocketProtocol] = [:]

    private let logService: LogServiceProtocol
    private let managerService: SrtPortManagerServiceProtocol
    private let metricsService: SrtMetricsServiceProtocol

    private var pendingListener: SrtListenerContext? = nil
    private var pendingCaller: SrtCallerContext? = nil
    private var latestTimestamp: UInt32 = 0
    public let udpHeader: UdpHeader

    var state: ConnectionState
    let connection: NWConnection
    
    public var connectionState: ConnectionStates {
        state.name
    }
    
    public required init(updHeader: UdpHeader,
                         connection: NWConnection,
                         logService: LogServiceProtocol,
                         managerService: SrtPortManagerServiceProtocol,
                         metricsService: SrtMetricsServiceProtocol) {
        
        self.connection = connection
        self.udpHeader = updHeader
        self.logService = logService
        self.managerService = managerService
        self.metricsService = metricsService
        
        state = ConnectionSetupState()
        
    }
    
    public func handshake(address: IPv4Address) {
        
        if pendingCaller == nil {

            pendingCaller = SrtCallerContext(srtSocketID: UInt32.random(in: UInt32.min...UInt32.max),
                                             initialPacketSequenceNumber: 0,
                                             synCookie: 0,
                                             peerIpAddress: address.to16bytes(),
                                             encrypted: false,
                                             send: send(header:contents:),
                                             onSocketCreated: { socket in
                                                 self.sockets[socket.socketId] = socket
                                                 self.pendingCaller = nil
                                             })
            
        }
        
    }
    
    public func cancel() {
        if connection.state == .ready {
            
            managerService.removeConnection(header: udpHeader)
            
            connection.forceCancel()

        }
    }
    
    public func removeSocket(id: UInt32) {
        
        if let socket = sockets[id] {
            socket.shutdown()
        }
        
        sockets[id] = nil
        
    }
    
    public func start() {
        
        log("Starting Connection")
        
        if self.state.name == .setup {
            state.auto(self)
        }
        
    }

    public func sendFrame(frame: Data) {

        log("Sending \(frame.count) bytes")

    }

    func onStateChanged(_ state: NWConnection.State) {
        
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
            self.handleData(socketId: packet.destinationSocketID, frame: packet.data)
            
        } else {
            self.handleControl(packet: packet)
        }
        
    }
    
    func receiveNextMessage() {
        self.connection.receiveMessage { (data, context, isComplete, error) in
            
            if let error {
                print(error)
                return
            }
            
            guard let context else {
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
    
    public static func make(isHost: Bool,
                            serverIp: String,
                            serverPort: UInt16,
                            _ connection: NWConnection,
                            logService: LogServiceProtocol,
                            managerService: SrtPortManagerServiceProtocol,
                            metricsService: SrtMetricsServiceProtocol
    ) -> ConnectionContext? {
        
        guard let udpHeader = connection.makeUdpHeader(isHost: isHost) else {
            return nil
        }

        let context: ConnectionContext = .init(
            updHeader: udpHeader,
            connection: connection,
            logService: logService,
            managerService: managerService,
            metricsService: metricsService
        )
        
        connection.stateUpdateHandler = context.onStateChanged(_ :)
        
        return context
        
    }
}

extension ConnectionContext {
    
    private func getSocket(socketId: UInt32) -> SrtSocketProtocol? {
        
        guard let defaultSocket = self.sockets.values.first else {
            return nil
        }

        guard let matchedSocket = self.sockets[socketId] else {
            return defaultSocket
        }

        return matchedSocket

    }
    
    private func handleData(socketId: UInt32, frame: Data) {

        guard let socket = getSocket(socketId: socketId) else {
            return
        }
        
        guard let dataPacket = DataPacketFrame(frame) else {
            log("Data packet failed parsing")
            return
        }

        // let chunks = MpegTsParser.parseTSChunks(from: frame)
        
        let receiveMetrics: SrtMetricsModel = .init(bytesCount: dataPacket.data.count)
        metricsService.storeConnectionMetric(header: self.udpHeader, receive: receiveMetrics, send: nil)

        if let ackFrame = socket.handleData(packet: dataPacket) {
            let packet = SrtPacket(
                field1: ControlTypes.acknowledgement.asField,
                field2: ackFrame.acknowledgementNumber,
                timestamp: ackFrame.timestamp,
                socketID: socketId,
                contents: Data()
            )

            send(header: packet, contents: ackFrame.data.dropFirst(16))

            let sendMetrics: SrtMetricsModel = .init(bytesCount: dataPacket.data.count, dataPacketCount: 1)
            metricsService.storeConnectionMetric(header: self.udpHeader, receive: nil, send: sendMetrics)
        }

    }

    private func handleHandshake(handshake: SrtHandshake) {

        if let pendingListener {

            pendingListener.handleHandshake(handshake: handshake)

        } else if let pendingCaller {
            
            pendingCaller.handleHandshake(handshake: handshake)
            
        } else if handshake.isInductionRequest {
            
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
            
        } else {
            
            log("should never get here")
            
        }
        
    }
    
    private func handleControl(packet: SrtPacket) {
        
        if let _ = ShutdownFrame(packet.data) {
            self.cancel()
        }

        guard let controlPacket = ControlPacketFrame(packet.data),
              let controlType = ControlTypes(rawValue: controlPacket.controlType) else {
            log("Invalid control packet")
            return
        }
        
        let socketId = packet.destinationSocketID
        
        let _ = SrtSocketContext(encrypted: true,
                                             socketId: socketId,
                                             synCookie: self.udpHeader.cookie)
        
        switch controlType {
        case .handshake:
            guard let handshake = SrtHandshake(data: packet.contents) else {
                log("Invalid handshake packet")
                return
            }
            
            self.handleHandshake(handshake: handshake)
            
        case .keepAlive:

            handleKeepAlive(packet: packet)

        case .acknowledgement:
            log("Acknowledgement packet received")
        case .negativeAcknowledgement:
            log("Negative Acknowledgement packet received")
        case .congestionWarning:
            log("Congestion Warning packet received")
        case .shutdown:
            let socketId = controlPacket.destinationSocketID
            sockets.removeValue(forKey: socketId)
            if sockets.isEmpty {
                log("All sockets closed, cancelling connection")
                connection.cancel()
            } else {
                log("Socket \(socketId) shutdown, remaining sockets: \(sockets.count)")
            }
        case .ackack:
            guard let socket = getSocket(socketId: packet.destinationSocketID) else {
                return
            }
            
            if let ackAckFrame = AckAckFrame(packet.data) {
                socket.handleAckAck(ackAck: ackAckFrame)
            } else {
                log("Failed ACK ACK parsing")
            }
        case .dropRequest:
            log("Drop Request packet received")
        case .peerError:
            log("Peer Error packet received")
        case .userDefined:
            log("User Defined packet received")
        case .none:
            log("None packet type received")
        }
    }
    
    private func handleKeepAlive(packet: SrtPacket) {

        latestTimestamp = packet.timestamp + 100
        let packet = SrtPacket(field1: ControlTypes.keepAlive.asField, timestamp: latestTimestamp, socketID: packet.destinationSocketID, contents: Data())
        
        send(header: packet, contents: Data(repeating: 0, count: 4))

    }
    
    func send(header: SrtPacket, contents: Data) {
        
        guard connection.state == .ready else {
            print("ignoring \(connection.state)")
            return
        }
        
        let message = NWProtocolFramer.Message(srtPacket: header)
        let metadata = [message]
        let identifier = "\(self)"
        
        let context = NWConnection.ContentContext(identifier: identifier, metadata: metadata)
        self.connection.send(content: contents, contentContext: context, isComplete: true, completion: .idempotent)
    }
    
    func log(_ message: String) {
        logService.log("🛜", "Connection", message)
    }
    
    public func shutdown() {

        let socketId: UInt32

        if let socket = sockets.values.first {
            
            socketId = socket.socketId

        } else {

            socketId = 0

        }
        
        let packet = SrtPacket(
            field1: ControlTypes.shutdown.asField,
            timestamp: latestTimestamp + 100,
            socketID: socketId,
            contents: Data()
        )
        
        send(header: packet, contents: Data(repeating: 0, count: 4))
        managerService.removeConnection(header: udpHeader)

    }

}
