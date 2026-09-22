//
//  SrtSocket.swift
//  swift-srt
//
//  One SRT socket, owned by whoever subscribes to it. The connection routes raw
//  packets into `packets`; the owner pulls them on a task of its choosing and
//  calls `process`, which runs the protocol engine -- ACKs, keep-alive replies --
//  and hands back payload. The library spawns no task for this.
//

import Foundation

/// Deliberately not Sendable: it is transferred to exactly one owner through
/// the manager's `sockets` stream, and the compiler holds it to that.
public final class SrtSocket {

    public let socketId: UInt32
    public let peerSocketId: UInt32
    public let streamId: String?
    public let header: UdpHeader

    /// Packets addressed to this socket in arrival order, interleaved with the
    /// connection's 10 ms ticks and with payloads queued through `outbound`.
    public let events: AsyncStream<SrtSocketEvent>

    /// Hand this to whatever produces data; it is safe to use from any thread.
    public let outbound: SrtSocketOutbound

    private let engine: SrtSocketContext
    private let send: @Sendable (SrtPacket, Data) -> Void
    private let metrics: SrtMetricsServiceProtocol

    init(engine: SrtSocketContext,
         header: UdpHeader,
         events: AsyncStream<SrtSocketEvent>,
         inbox: AsyncStream<SrtSocketEvent>.Continuation,
         send: @escaping @Sendable (SrtPacket, Data) -> Void,
         metrics: SrtMetricsServiceProtocol) {

        self.engine = engine
        self.outbound = SrtSocketOutbound(inbox: inbox)
        self.socketId = engine.socketId
        self.peerSocketId = engine.peerSocketId
        self.streamId = engine.streamId
        self.header = header
        self.events = events
        self.send = send
        self.metrics = metrics
    }

    /// Runs one event through the protocol engine and returns whatever became
    /// deliverable: zero or more payloads, in order, once their time has come.
    public func process(_ event: SrtSocketEvent) -> [SrtFrame] {
        var frames: [SrtFrame] = []
        engine.handle(event: event, header: header, send: send, metrics: metrics) { frames.append($0) }
        return frames
    }

    /// Only meaningful from the task that calls `process`.
    public var statistics: SrtSocketStatistics { engine.statistics }

    /// Shorter key periods than libsrt's defaults (a key every 2^24 packets,
    /// announced 2^16 ahead). Only meaningful from the task that calls `process`.
    public func setKeyRefresh(rate: UInt32, preAnnounce: UInt32) {
        engine.setKeyRefresh(rate: rate, preAnnounce: preAnnounce)
    }
}

/// What the connection keeps for routing: just the way in. Sendable, so the
/// router can hold it after the handle itself has been handed off.
struct SocketRoute: Sendable {
    let peerSocketId: UInt32
    let inbox: AsyncStream<SrtSocketEvent>.Continuation

    func close() { inbox.finish() }
}
