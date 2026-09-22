//
//  SrtClock.swift
//  swift-srt
//
//  SRT timestamps are microseconds since the socket came up, in 32 bits, so
//  they wrap every 71 minutes. Every packet a connection sends is stamped
//  from one of these; every RTT it measures is a difference of two readings.
//

import Foundation

public final class SrtClock: Sendable {

    private let start: ContinuousClock.Instant

    public init() {
        start = ContinuousClock.now
    }

    /// Microseconds since the clock started, wrapped to 32 bits.
    public var now: UInt32 {
        let elapsed = ContinuousClock.now - start
        let components = elapsed.components
        let microseconds = UInt64(components.seconds) &* 1_000_000 &+ UInt64(components.attoseconds / 1_000_000_000_000)
        return UInt32(truncatingIfNeeded: microseconds)
    }

    /// Elapsed between two readings, wrap-aware. Only meaningful when the true
    /// gap is under 71 minutes, which every use here is.
    public static func elapsed(from earlier: UInt32, to later: UInt32) -> UInt32 {
        later &- earlier
    }
}
