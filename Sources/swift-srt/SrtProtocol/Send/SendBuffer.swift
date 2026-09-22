//
//  SendBuffer.swift
//  swift-srt
//
//  Holds what we have sent until the peer acknowledges it, hands packets back
//  for retransmission when the peer reports them lost, and gives up on ones
//  too old to matter. The sending half of reliability.
//

import Foundation

public struct SendBuffer: Sendable {

    public struct Entry: Sendable {
        public let packet: DataPacketFrame
        /// Our clock when the packet was first sent.
        public let sent: UInt32
        public var retransmissions = 0
    }

    public struct Statistics: Sendable, Equatable {
        public var sent = 0
        public var retransmitted = 0
        public var acknowledged = 0
        public var dropped = 0
        public var bytesSent = 0
        public var bytesRetransmitted = 0
        public var nakReferencesUnknown = 0
    }

    /// Next sequence number to assign.
    public private(set) var nextSequence: UInt32
    /// Next message number to assign.
    public private(set) var nextMessage: UInt32 = 1

    /// Oldest unacknowledged sequence, or nil when everything is acknowledged.
    public private(set) var oldest: UInt32?

    /// Newest sequence ever stored; the scans below stop here rather than at
    /// `nextSequence`, so storing without allocating still works.
    private var newest: UInt32?

    public private(set) var statistics = Statistics()

    private var entries: [UInt32: Entry] = [:]
    private let capacity: Int

    public init(initialSequence: UInt32, capacity: Int = 8192) {
        nextSequence = initialSequence
        self.capacity = capacity
    }

    public var count: Int { entries.count }
    public var isFull: Bool { entries.count >= capacity }

    /// Assigns the next sequence number, and a message number too when this
    /// packet starts a message.
    public mutating func allocate(message startsMessage: Bool = true) -> (sequence: UInt32, message: UInt32) {
        let sequence = nextSequence
        nextSequence = SrtSequence.increment(nextSequence)

        let message = nextMessage
        if startsMessage {
            nextMessage = (nextMessage + 1) & 0x03FF_FFFF
            if nextMessage == 0 { nextMessage = 1 }
        }
        return (sequence, message)
    }

    /// Records a packet that just went out for the first time.
    public mutating func store(_ packet: DataPacketFrame, sent: UInt32) {
        let sequence = packet.packetSequenceNumber
        entries[sequence] = Entry(packet: packet, sent: sent)
        if oldest == nil || SrtSequence.compare(sequence, oldest!) < 0 { oldest = sequence }
        if newest == nil || SrtSequence.compare(sequence, newest!) > 0 { newest = sequence }
        if SrtSequence.compare(nextSequence, sequence) <= 0 { nextSequence = SrtSequence.increment(sequence) }
        statistics.sent += 1
        statistics.bytesSent += packet.payload.count
    }

    /// The peer has everything before `sequence`; forget it.
    public mutating func acknowledge(upTo sequence: UInt32) {
        guard var cursor = oldest, let newest else { return }
        while SrtSequence.compare(cursor, sequence) < 0, SrtSequence.compare(cursor, newest) <= 0 {
            if entries.removeValue(forKey: cursor) != nil {
                statistics.acknowledged += 1
            }
            cursor = SrtSequence.increment(cursor)
        }
        oldest = entries.isEmpty ? nil : (entries[cursor] != nil ? cursor : entries.keys.min { SrtSequence.compare($0, $1) < 0 })
    }

    /// The packet to send again for a NAKed sequence, with its retransmit flag
    /// set, or nil if it is no longer held.
    public mutating func retransmission(of sequence: UInt32) -> DataPacketFrame? {
        guard var entry = entries[sequence] else {
            statistics.nakReferencesUnknown += 1
            return nil
        }
        entry.retransmissions += 1
        entries[sequence] = entry
        statistics.retransmitted += 1
        statistics.bytesRetransmitted += entry.packet.payload.count

        return DataPacketFrame(
            packetSequenceNumber: entry.packet.packetSequenceNumber,
            packetPosition: entry.packet.packetPosition,
            orderFlag: entry.packet.orderFlag,
            encryptionFlags: entry.packet.encryptionFlags,
            retransmittedFlag: true,
            messageNumber: entry.packet.messageNumber,
            timestamp: entry.packet.timestamp,
            destinationSocketID: entry.packet.destinationSocketID,
            payload: entry.packet.payload,
            authenticationTag: Data()
        )
    }

    /// Sender-side too-late drop: packets older than the latency budget will
    /// never be useful to the receiver, so stop holding them. Returns the
    /// ranges dropped, for DROPREQ.
    public mutating func dropExpired(now: UInt32, latencyMicroseconds: UInt32) -> [(first: UInt32, last: UInt32, message: UInt32)] {
        var dropped: [(UInt32, UInt32, UInt32)] = []
        guard var cursor = oldest, let newest else { return [] }

        while SrtSequence.compare(cursor, newest) <= 0 {
            guard let entry = entries[cursor] else {
                cursor = SrtSequence.increment(cursor)
                continue
            }
            guard SrtClock.elapsed(from: entry.sent, to: now) > latencyMicroseconds else { break }

            entries[cursor] = nil
            statistics.dropped += 1
            if let last = dropped.last, last.1 == SrtSequence.decrement(cursor), last.2 == entry.packet.messageNumber {
                dropped[dropped.count - 1].1 = cursor
            } else {
                dropped.append((cursor, cursor, entry.packet.messageNumber))
            }
            cursor = SrtSequence.increment(cursor)
        }

        oldest = entries.keys.min { SrtSequence.compare($0, $1) < 0 }
        return dropped.map { (first: $0.0, last: $0.1, message: $0.2) }
    }
}
