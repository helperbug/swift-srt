//
//  SrtPortManagerService.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation
import Network
import Observation
import Synchronization

@MainActor
@Observable
public final class SrtPortManagerService: SrtPortManagerServiceProtocol {

    @ObservationIgnored nonisolated public let icon = "⚓️"
    @ObservationIgnored nonisolated public let source = "Port Manager"

    @ObservationIgnored private let logService: LogServiceProtocol
    @ObservationIgnored private let metricsService: SrtMetricsServiceProtocol

    public private(set) var listeners: [NWEndpoint.Port: any SrtPortListenerProtocol] = [:]
    public private(set) var connections: [UdpHeader: any SrtConnectionProtocol] = [:]

    @ObservationIgnored nonisolated private let socketHandler = Mutex<(@Sendable (sending SrtSocket) -> Void)?>(nil)

    public init(logService: LogServiceProtocol, metricsService: SrtMetricsServiceProtocol) {
        self.logService = logService
        self.metricsService = metricsService
    }

    nonisolated public func log(_ message: String) {
        logService.log(icon, source, message)
    }

    public func addListener(endpoint: IPv4Address, port: NWEndpoint.Port, passphrase: String? = nil) {
        listeners[port] = SrtPortListenerContext(
            endpoint: endpoint,
            port: port,
            passphrase: passphrase,
            logService: logService,
            managerService: self,
            metricsService: metricsService
        )
    }

    public func connect(to address: IPv4Address, port: NWEndpoint.Port, streamId: String?, passphrase: String? = nil) {

        let connection = NWConnection(host: .ipv4(address), port: port, using: SrtPortListenerContext.parameters)
        let queue = DispatchQueue(label: "srt.caller.\(address):\(port)", qos: .userInitiated)
        let logService = self.logService
        let metricsService = self.metricsService

        /// The local endpoint, and so the connection's identity, is only known
        /// once the UDP socket is up. Build the context then and adopt it.
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                logService.log("⚓️", "Caller", "udp ready to \(address):\(port), local \(String(describing: connection.currentPath?.localEndpoint))")
                guard let self else { connection.cancel(); return }
                guard let context = ConnectionContext.make(isHost: false, connection, queue: queue,
                                                           passphrase: passphrase,
                                                           logService: logService,
                                                           managerService: self,
                                                           metricsService: metricsService) else {
                    logService.log("⚓️", "Caller", "could not describe connection to \(address):\(port); endpoint \(connection.endpoint), path \(String(describing: connection.currentPath))")
                    connection.cancel()
                    return
                }
                logService.log("⚓️", "Caller", "handshaking as \(context.udpHeader.sourceIp):\(context.udpHeader.sourcePort) → \(context.udpHeader.destinationIp):\(context.udpHeader.destinationPort)")
                context.adoptReady()
                context.handshake(address: address, streamId: streamId)
                let header = context.udpHeader
                Task { @MainActor in self.addConnection(header: header, connection: context) }

            case .failed(let error):
                logService.log("⚓️", "Caller", "connect to \(address):\(port) failed: \(error)")
                connection.cancel()

            case .waiting(let error):
                logService.log("⚓️", "Caller", "connect to \(address):\(port) waiting: \(error)")

            default:
                logService.log("⚓️", "Caller", "connect to \(address):\(port) state \(state)")
            }
        }

        connection.start(queue: queue)
    }

    public func rendezvous(with address: IPv4Address, port: NWEndpoint.Port, localPort: NWEndpoint.Port, streamId: String?, passphrase: String? = nil) {

        let parameters = SrtPortListenerContext.parameters
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: localPort)
        parameters.allowLocalEndpointReuse = true

        let connection = NWConnection(host: .ipv4(address), port: port, using: parameters)
        let queue = DispatchQueue(label: "srt.rendezvous.\(address):\(port)", qos: .userInitiated)
        let logService = self.logService
        let metricsService = self.metricsService

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let self else { connection.cancel(); return }
                guard let context = ConnectionContext.make(isHost: false, connection, queue: queue,
                                                           passphrase: passphrase,
                                                           logService: logService,
                                                           managerService: self,
                                                           metricsService: metricsService) else {
                    logService.log("⚓️", "Rendezvous", "could not describe connection to \(address):\(port)")
                    connection.cancel()
                    return
                }
                logService.log("⚓️", "Rendezvous", "waving as \(context.udpHeader.sourceIp):\(context.udpHeader.sourcePort) → \(address):\(port)")
                context.adoptReady()
                context.rendezvous(address: address, streamId: streamId)
                let header = context.udpHeader
                Task { @MainActor in self.addConnection(header: header, connection: context) }

            case .failed(let error):
                logService.log("⚓️", "Rendezvous", "to \(address):\(port) failed: \(error)")
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    public func addConnection(header: UdpHeader, connection: any SrtConnectionProtocol) {
        connections[header] = connection
    }

    nonisolated public func onSocket(_ handler: @escaping @Sendable (sending SrtSocket) -> Void) {
        socketHandler.withLock { $0 = handler }
    }

    /// Reader thread. A socket with nobody subscribed is dropped: its inbox
    /// buffers, its keep-alives go unanswered, and the peer times it out.
    nonisolated public func addSocket(_ socket: sending SrtSocket) {
        guard let handler = socketHandler.withLock({ $0 }) else { return }
        handler(socket)
    }

    public func removeListener(port: NWEndpoint.Port) {
        guard let listener = listeners[port] else { return }

        for header in connections.keys where header.destinationPort == port.rawValue {
            removeConnection(header: header)
        }

        listener.close()
        listeners[port] = nil
    }

    public func removeConnection(header: UdpHeader) {
        guard let connection = connections.removeValue(forKey: header) else { return }
        connection.cancel()
    }

    public func shutdown(port: NWEndpoint.Port? = nil) {
        for listener in listeners.values where port == nil || listener.port == port {
            listener.close()
        }
    }

    public func shutdownConnection(header: UdpHeader) {
        guard let connection = connections[header] else { return }
        connection.shutdown()
    }

}
