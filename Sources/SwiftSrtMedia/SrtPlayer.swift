//
//  SrtPlayer.swift
//  swift-srt
//
//  Observable model for a receiving player: listens, accepts sockets, and
//  feeds each one's video into a renderer.
//

#if !os(watchOS)

import Foundation
import Network
import Observation
import SwiftSrt

@MainActor
@Observable
public final class SrtPlayer {

    public let renderer: SrtVideoRenderer
    public let stats = TransportStats()

    @ObservationIgnored public let logService = LogService()
    @ObservationIgnored public let metricsService: SrtMetricsService
    @ObservationIgnored public let manager: SrtPortManagerService

    public private(set) var port: UInt16?
    public private(set) var sockets: [UInt32: SocketPipeline] = [:]

    /// Per-socket protocol statistics, refreshed by each pipeline as it runs.
    public private(set) var socketStatistics: [UInt32: SrtSocketStatistics] = [:]

    public init(presentationDelayMs: Int = 150, traceURL: URL? = nil) {
        renderer = SrtVideoRenderer(presentationDelayMs: presentationDelayMs, traceURL: traceURL)
        metricsService = SrtMetricsService(logService: logService, interval: 10)
        manager = SrtPortManagerService(logService: logService, metricsService: metricsService)
    }

    /// Listens on `port` and renders whatever connects.
    public func listen(on port: UInt16, passphrase: String? = nil) {
        guard let endpoint = IPv4Address("0.0.0.0"), let listenPort = NWEndpoint.Port(rawValue: port) else { return }
        subscribe()
        manager.addListener(endpoint: endpoint, port: listenPort, passphrase: passphrase)
        self.port = port
    }

    /// Calls a listener and renders what it sends.
    public func connect(to address: IPv4Address, port: UInt16, streamId: String? = nil, passphrase: String? = nil) {
        guard let remotePort = NWEndpoint.Port(rawValue: port) else { return }
        subscribe()
        manager.connect(to: address, port: remotePort, streamId: streamId, passphrase: passphrase)
    }

    private func subscribe() {
        let renderer = self.renderer
        let stats = self.stats

        manager.onSocket { [weak self] socket in
            let pipeline = SocketPipeline(socket: socket, stats: stats, deliver: { unit in
                renderer.render(unit)
            }, report: { id, statistics in
                Task { @MainActor in self?.socketStatistics[id] = statistics }
            })
            Task { @MainActor in self?.sockets[pipeline.socketId] = pipeline }
        }
    }

    public func stop() {
        for pipeline in sockets.values { pipeline.cancel() }
        sockets.removeAll()
        if let port, let listenPort = NWEndpoint.Port(rawValue: port) {
            manager.removeListener(port: listenPort)
        }
        port = nil
    }

    /// One line for a status bar or a log.
    public var summary: String {
        let transport = stats.snapshot
        return "\(renderer.summary)  sockets \(sockets.count)  bytes \(transport.bytes)"
    }
}

#endif
