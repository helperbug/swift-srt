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

import Combine
import Foundation
import Network

public class ConnectionContext: SrtConnectionProtocol {
    
    private let managerService: SrtPortManagerServiceProtocol
    private let metricsService: SrtMetricsServiceProtocol

    public var onCanceled: (UdpHeader) -> Void
    public var sockets: [UInt32: SrtSocketProtocol] = [:]
    var state: ConnectionState
    private var pendingListener: SrtListenerContext? = nil
    private let onDataPacket: (DataPacketFrame) -> Void
    private var timer: AnyCancellable? = nil
    private var metrics: SrtMetrics = .init()
    
    private let _udpHeader: UdpHeader
    let connection: NWConnection
    
    @Published private var _uptime: TimeInterval = 0
    public var uptime: AnyPublisher<TimeInterval, Never> {
        $_uptime.eraseToAnyPublisher()
    }
    
    @Published private var _receiveMetrics: SrtMetricsModel = .blank
    public var receiveMetrics: AnyPublisher<SrtMetricsModel, Never> {
        $_receiveMetrics.eraseToAnyPublisher()
    }
    
    @Published private var _sendMetrics: SrtMetricsModel = .blank
    public var sendMetrics: AnyPublisher<SrtMetricsModel, Never> {
        $_sendMetrics.eraseToAnyPublisher()
    }

    public var connectionState: ConnectionStates {
        state.name
    }

    public var udpHeader: UdpHeader {
        _udpHeader
    }
    
    public required init(updHeader: UdpHeader,
                         connection: NWConnection,
                         managerService: SrtPortManagerServiceProtocol,
                         metricsService: SrtMetricsServiceProtocol,
                         onCanceled: @escaping (UdpHeader) -> Void,
                         onDataPacket: @escaping (DataPacketFrame) -> Void) {
        
        self.connection = connection
        self._udpHeader = updHeader
        self.managerService = managerService
        self.metricsService = metricsService
        self.onCanceled = onCanceled
        self.onDataPacket = onDataPacket
        
        state = ConnectionSetupState()
        
//        self.timer = Timer.publish(every: 1.0, on: .main, in: .common)
//            .autoconnect()
//            .sink { _ in
//                self.gong()
//            }
    }

//    private func gong() {
//        _uptime += 1
//        
//        let currentMetrics = metrics
//        metrics = .init()
//
//        let (receive, send) = currentMetrics.capture()
//        _receiveMetrics = receive
//        _sendMetrics = send
//    }
    
    private func updateMetrics() {
        
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
    
    deinit {
        if let timer {
            timer.cancel()
        }
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
                     managerService: SrtPortManagerServiceProtocol,
                     metricsService: SrtMetricsServiceProtocol,
                     onCanceled: @escaping (UdpHeader) -> Void,
                     onDataPackat: @escaping (DataPacketFrame) -> Void
    ) -> ConnectionContext? {
        
        guard let updHeader = connection.makeUdpHeader() else {
            return nil
        }
        
        let context: ConnectionContext = .init(
            updHeader: updHeader,
            connection: connection,
            managerService: managerService,
            metricsService: metricsService,
            onCanceled: onCanceled,
            onDataPacket: onDataPackat
        )
        
        connection.stateUpdateHandler = context.onStateChanged(_ :)
        
        return context
        
    }
}

extension ConnectionContext { // handlers
    
    private func handleData(socketId: UInt32, frame: Data) {

        guard let defaultSocket = self.sockets.values.first else {
            print("fatal error")
            return
        }
        
        guard let dataPacket = DataPacketFrame(frame) else {
            print("bad data")
            return
        }

        self.onDataPacket(dataPacket)
        
        let receiveMetrics: SrtMetricsModel = .init(bytesCount: dataPacket.data.count)
        metricsService.storeConnectionMetric(header: self.udpHeader, receive: receiveMetrics, send: nil)
        
        metrics.receiveBytesCount += dataPacket.data.count
        
        if let matchedSocket = self.sockets[socketId] {
            
            matchedSocket.handleData(packet: dataPacket)
            
        } else {
            
            defaultSocket.handleData(packet: dataPacket)
            
        }
        
        onDataPacket(dataPacket)
        
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
        
        if let shutdown = ShutdownFrame(packet.data) {
            print("shutdown \(self.udpHeader) \(shutdown.destinationSocketID)")
            print("shut'r down")
            self.onCanceled(self.udpHeader)
        }

        guard let controlPacket = ControlPacketFrame(packet.data),
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
