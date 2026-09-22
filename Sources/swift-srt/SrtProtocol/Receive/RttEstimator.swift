//
//  RttEstimator.swift
//  swift-srt
//
//  Smoothed round-trip time, as the spec has it: each sample moves RTT by
//  an eighth and its variance by a quarter.
//

import Foundation

public struct RttEstimator: Sendable {

    /// Microseconds.
    public private(set) var rtt: UInt32
    public private(set) var variance: UInt32
    public private(set) var samples = 0

    public init(initialRtt: UInt32 = 100_000, initialVariance: UInt32 = 50_000) {
        rtt = initialRtt
        variance = initialVariance
    }

    public mutating func add(sample: UInt32) {
        samples += 1

        if samples == 1 {
            rtt = sample
            variance = sample / 2
            return
        }

        let deviation = rtt > sample ? rtt - sample : sample - rtt
        variance = (variance * 3 + deviation) / 4
        rtt = (rtt * 7 + sample) / 8
    }

    /// How long to wait before asking again for something already asked for.
    /// Half of RTT + 4 RTTVar, floored so a fast link does not NAK-storm.
    public var nakInterval: UInt32 {
        max(20_000, (rtt + 4 * variance) / 2)
    }
}
