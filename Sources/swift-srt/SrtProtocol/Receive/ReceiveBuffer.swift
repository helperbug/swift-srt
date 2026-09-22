//
//  ReceiveBuffer.swift
//  swift-srt
//
//  Holds data packets by sequence number, notices what is missing, and
//  releases packets in order when their delivery time comes. This is the
//  reordering and TSBPD half of reliability; the loss list it keeps is what
//  the NAKs are built from.
//

import Foundation

public struct ReceiveBuffer: Sendable {

    public struct Entry: Sendable {
        public let packet: DataPacketFrame
        /// Local clock reading when the packet arrived.
        public let arrival: UInt32
    }

    public enum InsertResult: Sendable, Equatable {
        case stored
        case duplicate
        /// Before the delivery point; it was already dropped or delivered.
        case belated
        /// Further ahead than the buffer can hold.
        case overflow
    }

    public struct LossRange: Sendable, Equatable {
        public let first: UInt32
        public let last: UInt32
        /// Local clock when the range was first noticed, for NAK pacing.
        public var reported: UInt32
    }

    public struct Statistics: Sendable, Equatable {
        public var received = 0
        public var retransmitted = 0
        public var duplicates = 0
        public var belated = 0
        public var overflowed = 0
        public var lost = 0
        public var dropped = 0
        public var delivered = 0
        public var bytesReceived = 0
        public var bytesDelivered = 0
    }

    /// Next sequence number to deliver. Everything before it is gone.
    public private(set) var deliveryPoint: UInt32

    /// Highest sequence number seen so far, or nil until the first packet.
    public private(set) var highest: UInt32?

    public private(set) var statistics = Statistics()

    /// Missing packets between the delivery point and the highest received.
    public private(set) var lossList: [LossRange] = []

    private var entries: [UInt32: Entry] = [:]
    private let capacity: Int

    /// TSBPD state: the peer's timestamp for the first packet, our clock when
    /// it arrived, and the latency to hold everything back by. Zero latency
    /// delivers whatever is contiguous.
    private var peerTimestampBase: UInt32?
    private var arrivalBase: UInt32?
    public let latencyMicroseconds: UInt32

    /// Drift tracing. The peer's clock and ours tick at slightly different
    /// rates; left alone, the delivery times walk away from the arrivals and
    /// either latency grows or packets go late. Every `driftSampleCount`
    /// packets the average error is folded back into the arrival base.
    private var driftAccumulator: Int64 = 0
    private var driftSamples = 0
    public private(set) var driftMicroseconds: Int32 = 0
    public private(set) var driftCorrections = 0
    private static let driftSampleCount = 1000

    public init(initialSequence: UInt32, capacity: Int = 8192, latencyMicroseconds: UInt32) {
        deliveryPoint = initialSequence
        self.capacity = capacity
        self.latencyMicroseconds = latencyMicroseconds
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    // MARK: Insert

    public mutating func insert(_ packet: DataPacketFrame, arrival: UInt32) -> InsertResult {

        let sequence = packet.packetSequenceNumber

        if SrtSequence.compare(sequence, deliveryPoint) < 0 {
            statistics.belated += 1
            return .belated
        }

        let ahead = SrtSequence.offset(from: deliveryPoint, to: sequence)
        guard ahead < capacity else {
            statistics.overflowed += 1
            return .overflow
        }

        if entries[sequence] != nil {
            statistics.duplicates += 1
            return .duplicate
        }

        if peerTimestampBase == nil {
            peerTimestampBase = packet.timestamp
            arrivalBase = arrival
        }

        entries[sequence] = Entry(packet: packet, arrival: arrival)
        statistics.received += 1
        traceDrift(packet: packet, arrival: arrival)
        statistics.bytesReceived += packet.payload.count
        if packet.retransmittedFlag {
            statistics.retransmitted += 1
        }

        /// A jump past the highest so far opens a hole; a fill closes part of one.
        if let previous = highest {
            if SrtSequence.compare(sequence, previous) > 0 {
                let expected = SrtSequence.increment(previous)
                if SrtSequence.compare(sequence, expected) > 0 {
                    let gap = SrtSequence.length(from: expected, to: SrtSequence.decrement(sequence))
                    statistics.lost += gap
                    lossList.append(LossRange(first: expected, last: SrtSequence.decrement(sequence), reported: 0))
                }
                highest = sequence
            } else {
                removeFromLoss(sequence)
            }
        } else {
            highest = sequence
            /// First packet after the handshake's ISN may itself be late.
            if SrtSequence.compare(sequence, deliveryPoint) > 0 {
                let gap = SrtSequence.length(from: deliveryPoint, to: SrtSequence.decrement(sequence))
                statistics.lost += gap
                lossList.append(LossRange(first: deliveryPoint, last: SrtSequence.decrement(sequence), reported: 0))
            }
        }

        return .stored
    }

    /// Error between when a packet arrived and when the timeline said it
    /// would. Only original transmissions count: a retransmission arrives
    /// late by definition.
    private mutating func traceDrift(packet: DataPacketFrame, arrival: UInt32) {
        guard !packet.retransmittedFlag, let peerTimestampBase, let arrivalBase else { return }

        let expected = arrivalBase &+ (packet.timestamp &- peerTimestampBase)
        driftAccumulator += Int64(Int32(bitPattern: arrival &- expected))
        driftSamples += 1

        guard driftSamples >= Self.driftSampleCount else { return }

        let average = Int32(driftAccumulator / Int64(driftSamples))
        driftMicroseconds = average
        self.arrivalBase = arrivalBase &+ UInt32(bitPattern: average)
        driftCorrections += 1
        driftAccumulator = 0
        driftSamples = 0
    }

    // MARK: Delivery

    /// When `sequence` is due to be handed up, on our clock. Nil before the
    /// first packet has anchored the timeline.
    public func deliveryTime(of packet: DataPacketFrame) -> UInt32? {
        guard let peerTimestampBase, let arrivalBase else { return nil }
        let sincePeerBase = packet.timestamp &- peerTimestampBase
        return arrivalBase &+ sincePeerBase &+ latencyMicroseconds
    }

    /// In-order packets whose delivery time has passed. Stops at the first
    /// hole; see `dropExpired` for what happens when a hole is not filled.
    public mutating func drain(now: UInt32) -> [DataPacketFrame] {

        var delivered: [DataPacketFrame] = []

        while let entry = entries[deliveryPoint] {

            if latencyMicroseconds > 0, let due = deliveryTime(of: entry.packet),
               SrtSequence.timeIsBefore(now, due) {
                break
            }

            delivered.append(entry.packet)
            entries[deliveryPoint] = nil
            statistics.delivered += 1
            statistics.bytesDelivered += entry.packet.payload.count
            deliveryPoint = SrtSequence.increment(deliveryPoint)
        }

        return delivered
    }

    /// Too-late packet drop: if the delivery point is a hole and the packet
    /// after it is already overdue, give up on the hole so playback continues.
    /// Returns how many sequence numbers were skipped.
    @discardableResult
    public mutating func dropExpired(now: UInt32) -> Int {

        guard entries[deliveryPoint] == nil, let highest else { return 0 }
        guard SrtSequence.compare(deliveryPoint, highest) <= 0 else { return 0 }

        /// Find the next packet we do have.
        var candidate = deliveryPoint
        while entries[candidate] == nil {
            if SrtSequence.compare(candidate, highest) >= 0 { return 0 }
            candidate = SrtSequence.increment(candidate)
        }

        guard let next = entries[candidate], let due = deliveryTime(of: next.packet),
              !SrtSequence.timeIsBefore(now, due) else {
            return 0
        }

        let skipped = SrtSequence.offset(from: deliveryPoint, to: candidate)
        for _ in 0..<skipped {
            removeFromLoss(deliveryPoint)
            deliveryPoint = SrtSequence.increment(deliveryPoint)
        }
        statistics.dropped += skipped
        return skipped
    }

    /// The sender asked us to forget a range (DROPREQ).
    public mutating func drop(from first: UInt32, to last: UInt32) {
        var sequence = first
        while SrtSequence.compare(sequence, last) <= 0 {
            if SrtSequence.compare(sequence, deliveryPoint) >= 0, entries[sequence] == nil {
                removeFromLoss(sequence)
                statistics.dropped += 1
            }
            if sequence == last { break }
            sequence = SrtSequence.increment(sequence)
        }
        if SrtSequence.compare(deliveryPoint, first) >= 0, SrtSequence.compare(deliveryPoint, last) <= 0 {
            deliveryPoint = SrtSequence.increment(last)
        }
    }

    // MARK: ACK support

    /// First sequence number not yet received in order: what an ACK reports.
    public var acknowledgeSequence: UInt32 {
        var sequence = deliveryPoint
        while entries[sequence] != nil {
            sequence = SrtSequence.increment(sequence)
        }
        return sequence
    }

    /// Packets we could still take before overflowing.
    public var availableCapacity: Int {
        guard let highest else { return capacity }
        return max(0, capacity - SrtSequence.offset(from: deliveryPoint, to: highest) - 1)
    }

    // MARK: Loss list

    /// Ranges not reported within `interval` of `now`, marked as reported.
    public mutating func lossesToReport(now: UInt32, interval: UInt32) -> [LossRange] {
        var due: [LossRange] = []
        for index in lossList.indices {
            let range = lossList[index]
            if range.reported == 0 || SrtClock.elapsed(from: range.reported, to: now) >= interval {
                lossList[index].reported = now
                due.append(lossList[index])
            }
        }
        return due
    }

    private mutating func removeFromLoss(_ sequence: UInt32) {
        guard let index = lossList.firstIndex(where: {
            SrtSequence.compare(sequence, $0.first) >= 0 && SrtSequence.compare(sequence, $0.last) <= 0
        }) else { return }

        let range = lossList.remove(at: index)

        if SrtSequence.compare(range.first, sequence) < 0 {
            lossList.insert(LossRange(first: range.first, last: SrtSequence.decrement(sequence), reported: range.reported), at: index)
        }
        if SrtSequence.compare(sequence, range.last) < 0 {
            let after = LossRange(first: SrtSequence.increment(sequence), last: range.last, reported: range.reported)
            let position = SrtSequence.compare(range.first, sequence) < 0 ? index + 1 : index
            lossList.insert(after, at: position)
        }
    }
}

extension SrtSequence {
    /// Wrap-aware "is `now` before `deadline`" on the 32-bit microsecond clock.
    static func timeIsBefore(_ now: UInt32, _ deadline: UInt32) -> Bool {
        Int32(bitPattern: now &- deadline) < 0
    }
}
