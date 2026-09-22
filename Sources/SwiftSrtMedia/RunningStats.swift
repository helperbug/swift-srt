//
//  RunningStats.swift
//  swift-srt
//

import Foundation
import Synchronization

/// Welford running statistics, in whatever unit the caller feeds it.
public struct RunningStats: Sendable {

    public private(set) var count = 0
    private var mean = 0.0
    private var m2 = 0.0
    public private(set) var minimum = Double.infinity
    public private(set) var maximum = -Double.infinity

    public init() { }

    public mutating func add(_ x: Double) {
        count += 1
        let delta = x - mean
        mean += delta / Double(count)
        m2 += delta * (x - mean)
        minimum = min(minimum, x)
        maximum = max(maximum, x)
    }

    public var average: Double { mean }
    public var standardDeviation: Double { count > 1 ? (m2 / Double(count - 1)).squareRoot() : 0 }

    public var summary: String {
        count == 0 ? "n=0" : String(format: "n=%d mean=%.1f σ=%.1f min=%.1f max=%.1f", count, mean, standardDeviation, minimum, maximum)
    }
}

/// Transport-side timing, shared between a socket task and whatever displays it.
public final class TransportStats: Sendable {

    private struct State {
        var packets = RunningStats()
        var units = RunningStats()
        var lastPacket: ContinuousClock.Instant?
        var lastUnit: ContinuousClock.Instant?
        var bytes = 0
    }

    private let state = Mutex(State())

    public init() { }

    public func packetArrived(bytes: Int) {
        let now = ContinuousClock.now
        state.withLock { s in
            if let last = s.lastPacket { s.packets.add(Self.milliseconds(now - last)) }
            s.lastPacket = now
            s.bytes += bytes
        }
    }

    public func unitCompleted() {
        let now = ContinuousClock.now
        state.withLock { s in
            if let last = s.lastUnit { s.units.add(Self.milliseconds(now - last)) }
            s.lastUnit = now
        }
    }

    public var snapshot: (packets: RunningStats, units: RunningStats, bytes: Int) {
        state.withLock { ($0.packets, $0.units, $0.bytes) }
    }

    public static func milliseconds(_ duration: Duration) -> Double {
        let c = duration.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}
