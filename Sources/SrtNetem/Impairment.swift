//
//  Impairment.swift
//  swift-srt
//
//  Deterministic packet impairment decisions for the test proxy. Same seed,
//  same decisions, so a failing run can be replayed exactly.
//

import Foundation

/// SplitMix64: small, fast, and good enough to draw loss decisions from.
public struct SplitMix64: RandomNumberGenerator, Sendable {

    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// What to do to the stream, as probabilities per packet.
public struct ImpairmentProfile: Sendable, Equatable {

    /// Probability a packet is dropped outright.
    public var loss: Double

    /// Probability a packet is held back and sent after the next one.
    public var reorder: Double

    public init(loss: Double = 0, reorder: Double = 0) {
        self.loss = min(max(loss, 0), 1)
        self.reorder = min(max(reorder, 0), 1)
    }

    public static let clean = ImpairmentProfile()
}

/// Draws one decision per packet from a seeded generator.
public struct Impairment: Sendable {

    public enum Decision: Sendable, Equatable {
        case forward
        case drop
        case hold
    }

    public let profile: ImpairmentProfile
    private var generator: SplitMix64

    public init(profile: ImpairmentProfile, seed: UInt64) {
        self.profile = profile
        self.generator = SplitMix64(seed: seed)
    }

    public mutating func decide() -> Decision {
        let draw = Double.random(in: 0..<1, using: &generator)

        if draw < profile.loss {
            return .drop
        }

        if draw < profile.loss + profile.reorder {
            return .hold
        }

        return .forward
    }
}
