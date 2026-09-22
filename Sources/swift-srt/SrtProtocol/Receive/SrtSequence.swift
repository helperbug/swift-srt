//
//  SrtSequence.swift
//  swift-srt
//
//  Packet sequence numbers are 31 bits and wrap. Every comparison and
//  distance in the receive path goes through here so the wrap is handled in
//  exactly one place. Mirrors libsrt's CSeqNo.
//

import Foundation

public enum SrtSequence {

    public static let maximum: UInt32 = 0x7FFF_FFFF
    public static let count: UInt32 = 0x8000_0000

    /// Half the space; two numbers further apart than this are treated as
    /// having wrapped.
    private static let threshold: Int64 = 0x4000_0000

    /// Negative if `a` is before `b`, positive if after, zero if equal --
    /// as long as they are within half the space of each other.
    public static func compare(_ a: UInt32, _ b: UInt32) -> Int {
        let difference = Int64(a) - Int64(b)
        if abs(difference) < threshold {
            return difference < 0 ? -1 : (difference > 0 ? 1 : 0)
        }
        return difference < 0 ? 1 : -1
    }

    /// Distance from `from` to `to`, signed, wrap-aware.
    public static func offset(from: UInt32, to: UInt32) -> Int {
        let difference = Int64(to) - Int64(from)
        if abs(difference) < threshold {
            return Int(difference)
        }
        return Int(difference < 0 ? difference + Int64(count) : difference - Int64(count))
    }

    /// Number of packets in the inclusive range `first...last`.
    public static func length(from first: UInt32, to last: UInt32) -> Int {
        let raw = offset(from: first, to: last)
        return raw >= 0 ? raw + 1 : 0
    }

    public static func increment(_ sequence: UInt32, by delta: Int = 1) -> UInt32 {
        let value = (Int64(sequence) + Int64(delta)) % Int64(count)
        return UInt32(value < 0 ? value + Int64(count) : value)
    }

    public static func decrement(_ sequence: UInt32, by delta: Int = 1) -> UInt32 {
        increment(sequence, by: -delta)
    }
}
