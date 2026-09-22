//
//  SocketPipeline.swift
//  swift-srt
//
//  One transport-and-demux loop per socket, on its own task. Owns the socket
//  and the demuxer; what it emits is plain data. This is the subscriber the
//  transport hands a socket to -- the library itself spawns nothing.
//

import Foundation
import SwiftSrt

public final class SocketPipeline: Sendable {

    public let socketId: UInt32
    public let streamId: String?
    private let task: Task<Void, Never>

    public init(socket: sending SrtSocket,
                stats: TransportStats,
                deliver: @escaping @MainActor @Sendable (AccessUnit) -> Void,
                report: (@Sendable (UInt32, SrtSocketStatistics) -> Void)? = nil) {

        self.socketId = socket.socketId
        self.streamId = socket.streamId

        task = Task.detached(priority: .userInitiated) {
            let demuxer = TsDemuxer()
            var lastReport = ContinuousClock.now

            for await event in socket.events {
                for frame in socket.process(event) {
                    stats.packetArrived(bytes: frame.payload.count)

                    for unit in demuxer.append(frame.payload) {
                        stats.unitCompleted()
                        await deliver(unit)
                    }
                }

                if let report, ContinuousClock.now - lastReport > .seconds(1) {
                    lastReport = ContinuousClock.now
                    report(socket.socketId, socket.statistics)
                }
            }
        }
    }

    public func cancel() { task.cancel() }
}
