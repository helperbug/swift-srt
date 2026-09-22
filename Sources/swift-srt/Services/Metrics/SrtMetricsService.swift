//
//  SrtMetricsService.swift
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

import Combine
import Foundation
import Network
import Synchronization

/// Accumulates counters under a lock on the hot path and publishes a snapshot
/// on a timer. Nothing here hops isolation per packet.
public final class SrtMetricsService: SrtMetricsServiceProtocol {

    public let icon = "⏱️"
    public let source = "Metrics"

    private let logService: LogServiceProtocol

    private struct Stores {
        var listeners: [NWEndpoint.Port: SrtMetrics] = [:]
        var connections: [UdpHeader: SrtMetrics] = [:]
        var sockets: [SocketKey: SrtMetrics] = [:]
    }

    private let stores = Mutex(Stores())

    public let listenerMetrics: AsyncStream<ListenerMetrics>
    public let connectionMetrics: AsyncStream<ConnectionMetrics>
    public let socketMetrics: AsyncStream<SocketMetrics>

    private let listenerContinuation: AsyncStream<ListenerMetrics>.Continuation
    private let connectionContinuation: AsyncStream<ConnectionMetrics>.Continuation
    private let socketContinuation: AsyncStream<SocketMetrics>.Continuation

    private let flushTask: Mutex<Task<Void, Never>?> = Mutex(nil)

    public init(logService: LogServiceProtocol, interval: TimeInterval) {
        self.logService = logService

        (listenerMetrics, listenerContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        (connectionMetrics, connectionContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        (socketMetrics, socketContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                self?.flushMetrics()
            }
        }
        flushTask.withLock { $0 = task }
    }

    deinit {
        flushTask.withLock { $0?.cancel() }
    }

    public func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        stores.withLock { stores in
            stores.connections[header, default: SrtMetrics()].delta(receive: receive, send: send)
            let port = NWEndpoint.Port(integerLiteral: header.destinationPort)
            stores.listeners[port, default: SrtMetrics()].delta(receive: receive, send: send)
        }
    }

    public func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        stores.withLock { stores in
            stores.sockets[SocketKey(header: header, socketId: socketId), default: SrtMetrics()]
                .delta(receive: receive, send: send)
        }
    }

    public func log(_ message: String) {
        logService.log(icon, source, message)
    }

    public func flushMetrics() {
        let snapshot = stores.withLock { stores -> Stores in
            let copy = stores
            stores = Stores()
            return copy
        }

        for (port, metrics) in snapshot.listeners {
            let (receive, send) = metrics.capture()
            listenerContinuation.yield(ListenerMetrics(port: port, receive: receive, send: send))
        }
        for (header, metrics) in snapshot.connections {
            let (receive, send) = metrics.capture()
            connectionContinuation.yield(ConnectionMetrics(header: header, receive: receive, send: send))
        }
        for (key, metrics) in snapshot.sockets {
            let (receive, send) = metrics.capture()
            socketContinuation.yield(SocketMetrics(header: key.header, socketId: key.socketId, receive: receive, send: send))
        }
    }

    private struct SocketKey: Hashable {
        let header: UdpHeader
        let socketId: UInt32
    }
}
