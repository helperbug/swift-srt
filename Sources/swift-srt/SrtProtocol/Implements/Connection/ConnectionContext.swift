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

    /// `UdpHeader.cookie` mixes in the wall clock at one-minute accuracy, so reading it
    /// twice can yield two different cookies. Mint it once per connection and compare
    /// the caller's conclusion request against that fixed value.
    let synCookie: UInt32

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
        self.synCookie = updHeader.cookie
        self.logService = logService
        self.managerService = managerService
        self.metricsService = metricsService
        
        state = ConnectionSetupState()
        
    }
    
    public func handshake(address: IPv4Address, streamId: String? = nil) {

        guard pendingCaller == nil else {
            return
        }

        /// Socket ID 0 is reserved to mean "connection request", so never pick it.
        let caller = SrtCallerContext(srtSocketID: UInt32.random(in: 1...UInt32.max),
                                      initialPacketSequenceNumber: 0,
                                      synCookie: 0,
                                      peerIpAddress: address.to16bytes(),
                                      encrypted: false,
                                      streamId: streamId,
                                      send: send(header:contents:),
                                      onSocketCreated: { [weak self] socket in
                                          guard let self else { return }
                                          self.sockets[socket.socketId] = socket
                                          self.pendingCaller = nil
                                      })

        /// Assign before starting: the induction response can arrive as soon as the
        /// request goes out, and it has to find the caller here.
        pendingCaller = caller
        caller.start()

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
    
    /// Packets are dispatched strictly by destination socket ID. Falling back to
    /// an arbitrary socket would let a packet addressed to nobody drive the state
    /// of an unrelated stream on the same connection.
    private func getSocket(socketId: UInt32) -> SrtSocketProtocol? {

        self.sockets[socketId]

    }
    
    private func handleData(socketId: UInt32, frame: Data) {

        guard let socket = getSocket(socketId: socketId) else {
            return
        }
        
        guard let dataPacket = DataPacketFrame(frame) else {
            log("Data packet failed parsing")
            return
        }

        /// Hand the payload to the application. Without this the received bytes
        /// stop here and nothing downstream ever sees the stream.
        managerService.addFrame(
            header: self.udpHeader,
            socketId: socketId,
            messageId: dataPacket.messageNumber,
            frame: dataPacket.payload
        )

        let receiveMetrics: SrtMetricsModel = .init(bytesCount: dataPacket.data.count)
        metricsService.storeConnectionMetric(header: self.udpHeader, receive: receiveMetrics, send: nil)

        if let ackFrame = socket.handleData(packet: dataPacket) {
            let packet = SrtPacket(
                field1: ControlTypes.acknowledgement.asField,
                field2: ackFrame.acknowledgementNumber,
                timestamp: ackFrame.timestamp,
                socketID: socket.peerSocketId,
                contents: Data()
            )

            send(header: packet, contents: ackFrame.data.dropFirst(16))

            let sendMetrics: SrtMetricsModel = .init(bytesCount: dataPacket.data.count, dataPacketCount: 1)
            metricsService.storeConnectionMetric(header: self.udpHeader, receive: nil, send: sendMetrics)
        }

    }

    private func handleHandshake(handshake: SrtHandshake, destinationSocketID: UInt32) {

        /// Once a socket exists for this ID the handshake that built it is done;
        /// a further one is a late retransmission and must not reopen anything.
        if destinationSocketID != 0, sockets[destinationSocketID] != nil {

            log("Ignoring handshake for established socket \(destinationSocketID)")
            return

        }

        if let pendingListener {

            pendingListener.handleHandshake(handshake: handshake)

        } else if let pendingCaller {
            
            pendingCaller.handleHandshake(handshake: handshake)
            
        } else if handshake.isInductionRequest {

            guard let peerIpAddress = self.udpHeader.sourceIp.ipStringToData else {
                log("Cannot parse peer address \(self.udpHeader.sourceIp)")
                return
            }

            /// The listener answers with a socket ID of its own; the caller's ID from
            /// the induction request becomes the destination for everything we send.
            let listener = SrtListenerContext(
                srtSocketID: UInt32.random(in: 1...UInt32.max),
                peerSocketID: handshake.srtSocketID,
                initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
                synCookie: self.synCookie,
                peerIpAddress: peerIpAddress,
                encrypted: false,
                send: self.send(header:contents:),
                onSocketCreated: { [weak self] socket in
                    guard let self else { return }
                    self.sockets[socket.socketId] = socket
                    self.pendingListener = nil
                })

            /// Assign before starting, so the conclusion request finds it here.
            self.pendingListener = listener
            listener.start()

        } else {
            
            log("should never get here")
            
        }
        
    }
    
    private func handleControl(packet: SrtPacket) {
        
        guard let controlPacket = ControlPacketFrame(packet.data),
              let controlType = ControlTypes(rawValue: controlPacket.controlType) else {
            log("Invalid control packet")
            return
        }
        
        switch controlType {
        case .handshake:
            guard let handshake = SrtHandshake(data: packet.contents) else {
                log("Invalid handshake packet")
                return
            }
            
            self.handleHandshake(handshake: handshake,
                                 destinationSocketID: packet.destinationSocketID)
            
        case .keepAlive:

            handleKeepAlive(packet: packet)

        case .acknowledgement:
            log("Acknowledgement packet received")
        case .negativeAcknowledgement:
            log("Negative Acknowledgement packet received")
        case .congestionWarning:
            log("Congestion Warning packet received")
        case .shutdown:
            let socketId = packet.destinationSocketID
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

        guard let socket = getSocket(socketId: packet.destinationSocketID) else {
            log("Ignoring keep-alive for unknown socket \(packet.destinationSocketID)")
            return
        }

        latestTimestamp = packet.timestamp + 100

        let reply = SrtPacket(
            field1: ControlTypes.keepAlive.asField,
            timestamp: latestTimestamp,
            socketID: socket.peerSocketId,
            contents: Data()
        )

        /// libsrt rejects a zero-length keep-alive body: it wants a CIF greater
        /// than zero and aligned to four bytes.
        send(header: reply, contents: Data(repeating: 0, count: 4))

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
            
            socketId = socket.peerSocketId

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
