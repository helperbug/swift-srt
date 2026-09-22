//
//  TsDemuxer.swift
//  swift-srt
//
//  Demultiplexes an MPEG-TS byte stream into elementary stream access units.
//
//  SRT carries MPEG-TS, so this is the first stage of turning received bytes
//  back into something a decoder can play.
//

import Foundation

/// Stream types carried in a PMT, limited to what this package can present.
public enum ElementaryStreamType: UInt8, Sendable {
    case h264 = 0x1B
    case hevc = 0x24
    case adtsAac = 0x0F
    case latmAac = 0x11

    public var isVideo: Bool {
        self == .h264 || self == .hevc
    }

    public var isAudio: Bool {
        self == .adtsAac || self == .latmAac
    }
}

/// One complete PES payload with its presentation timing.
public struct AccessUnit: Sendable {
    public let pid: UInt16
    public let streamType: ElementaryStreamType
    /// Presentation timestamp in 90 kHz ticks, if the PES header carried one.
    public let presentationTimeStamp: UInt64?
    /// Decode timestamp in 90 kHz ticks, if the PES header carried one.
    public let decodeTimeStamp: UInt64?
    public let data: Data
}

/// Turns a stream of 188-byte transport packets into access units.
///
/// Feed it whatever arrives, in whatever sized chunks; it buffers across calls
/// and resynchronises on the 0x47 sync byte if the stream is interrupted.
public final class TsDemuxer {

    public static let packetSize = 188
    public static let syncByte: UInt8 = 0x47

    private static let patPid: UInt16 = 0x0000
    private static let nullPid: UInt16 = 0x1FFF

    /// Bytes not yet forming a whole packet, consumed via `cursor` rather than
    /// by removing from the front: appending to the end while removing from the
    /// front makes the backing store walk forward and never release.
    private var buffer = Data()

    /// How far into `buffer` has been consumed.
    private var cursor = 0

    /// Compact once this much has been consumed, amortising the memmove.
    private static let compactionThreshold = 64 * 1024

    /// PID carrying the PMT, learned from the PAT.
    private var pmtPid: UInt16?

    /// Elementary stream PIDs and their types, learned from the PMT.
    private(set) public var streams: [UInt16: ElementaryStreamType] = [:]

    /// Partially assembled PES payloads, keyed by PID.
    private var pending: [UInt16: Data] = [:]

    /// Last continuity counter seen per PID, for discontinuity detection.
    private var continuity: [UInt16: UInt8] = [:]

    /// Number of packets dropped because the continuity counter jumped.
    private(set) public var discontinuities = 0

    /// Number of transport packets consumed.
    private(set) public var packetsProcessed = 0

    public init() { }

    /// Feeds bytes in and returns any access units they completed.
    public func append(_ data: Data) -> [AccessUnit] {

        buffer.append(data)

        var units: [AccessUnit] = []

        while let packet = nextPacket() {
            if let unit = process(packet: packet) {
                units.append(unit)
            }
        }

        compact()

        return units
    }

    /// Drops the consumed prefix. Clearing outright when everything has been
    /// consumed keeps the allocation for reuse without letting it grow.
    private func compact() {

        guard cursor > 0 else { return }

        if cursor >= buffer.count {
            buffer.removeAll(keepingCapacity: true)
            cursor = 0
        } else if cursor >= Self.compactionThreshold {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + cursor))
            cursor = 0
        }
    }

    /// Flushes any PES payload still being assembled. A PES packet with no
    /// declared length is only complete when the next one starts, so the tail of
    /// a stream needs an explicit flush.
    public func flush() -> [AccessUnit] {

        var units: [AccessUnit] = []

        for (pid, payload) in pending {
            if let streamType = streams[pid], let unit = makeAccessUnit(pid: pid, streamType: streamType, pes: payload) {
                units.append(unit)
            }
        }

        pending.removeAll()

        return units
    }

    // MARK: Packet framing

    /// Pulls one aligned 188-byte packet out of the buffer, resynchronising if
    /// the stream does not start on a sync byte.
    private func nextPacket() -> Data? {

        while buffer.count - cursor >= Self.packetSize {

            let start = buffer.startIndex + cursor

            if buffer[start] == Self.syncByte {
                cursor += Self.packetSize
                packetsProcessed += 1
                return buffer.subdata(in: start..<(start + Self.packetSize))
            }

            /// Lost alignment. Step forward looking for the next sync byte.
            cursor += 1
        }

        return nil
    }

    // MARK: Transport layer

    private func process(packet: Data) -> AccessUnit? {

        let bytes = [UInt8](packet)

        let payloadUnitStart = bytes[1] & 0x40 != 0
        let pid = (UInt16(bytes[1] & 0x1F) << 8) | UInt16(bytes[2])
        let adaptationControl = (bytes[3] & 0x30) >> 4
        let counter = bytes[3] & 0x0F

        guard pid != Self.nullPid else { return nil }

        /// Work out where the payload starts, stepping over any adaptation field.
        var offset = 4

        if adaptationControl == 0b10 || adaptationControl == 0b11 {
            guard offset < bytes.count else { return nil }
            let adaptationLength = Int(bytes[offset])
            offset += 1 + adaptationLength
        }

        /// 0b10 is adaptation only, so there is nothing further to read.
        guard adaptationControl == 0b01 || adaptationControl == 0b11,
              offset < bytes.count else {
            return nil
        }

        /// A repeated counter is a duplicate packet; a jump means loss. Only
        /// packets carrying payload increment it.
        if let previous = continuity[pid] {
            let expected = (previous &+ 1) & 0x0F
            if counter == previous {
                return nil
            }
            if counter != expected {
                discontinuities += 1
                /// Drop whatever was half assembled: it is now incomplete.
                pending[pid] = nil
            }
        }
        continuity[pid] = counter

        let payload = Data(bytes[offset...])

        if pid == Self.patPid {
            parsePat(payload: payload, payloadUnitStart: payloadUnitStart)
            return nil
        }

        if let pmtPid, pid == pmtPid {
            parsePmt(payload: payload, payloadUnitStart: payloadUnitStart)
            return nil
        }

        guard let streamType = streams[pid] else { return nil }

        return assemble(pid: pid,
                        streamType: streamType,
                        payload: payload,
                        payloadUnitStart: payloadUnitStart)
    }

    // MARK: Program tables

    /// Strips the pointer field that precedes a section in a packet with PUSI set.
    private func sectionBody(_ payload: Data, payloadUnitStart: Bool) -> Data? {

        guard payloadUnitStart, let pointer = payload.first else { return nil }

        let start = payload.index(payload.startIndex, offsetBy: 1 + Int(pointer), limitedBy: payload.endIndex)

        guard let start, start < payload.endIndex else { return nil }

        return Data(payload[start...])
    }

    private func parsePat(payload: Data, payloadUnitStart: Bool) {

        guard let section = sectionBody(payload, payloadUnitStart: payloadUnitStart) else { return }

        let bytes = [UInt8](section)

        guard bytes.count >= 8, bytes[0] == 0x00 else { return }

        let sectionLength = Int(UInt16(bytes[1] & 0x0F) << 8 | UInt16(bytes[2]))

        /// Entries start after the 8 byte section header and stop before the CRC.
        let entriesStart = 8
        let entriesEnd = min(3 + sectionLength - 4, bytes.count)

        var index = entriesStart

        while index + 4 <= entriesEnd {
            let programNumber = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            let pid = (UInt16(bytes[index + 2] & 0x1F) << 8) | UInt16(bytes[index + 3])

            /// Program 0 is the network PID, not a program map.
            if programNumber != 0 {
                pmtPid = pid
                return
            }

            index += 4
        }
    }

    private func parsePmt(payload: Data, payloadUnitStart: Bool) {

        guard let section = sectionBody(payload, payloadUnitStart: payloadUnitStart) else { return }

        let bytes = [UInt8](section)

        guard bytes.count >= 12, bytes[0] == 0x02 else { return }

        let sectionLength = Int(UInt16(bytes[1] & 0x0F) << 8 | UInt16(bytes[2]))
        let programInfoLength = Int(UInt16(bytes[10] & 0x0F) << 8 | UInt16(bytes[11]))

        var index = 12 + programInfoLength
        let end = min(3 + sectionLength - 4, bytes.count)

        var discovered: [UInt16: ElementaryStreamType] = [:]

        while index + 5 <= end {
            let rawType = bytes[index]
            let pid = (UInt16(bytes[index + 1] & 0x1F) << 8) | UInt16(bytes[index + 2])
            let esInfoLength = Int(UInt16(bytes[index + 3] & 0x0F) << 8 | UInt16(bytes[index + 4]))

            if let streamType = ElementaryStreamType(rawValue: rawType) {
                discovered[pid] = streamType
            }

            index += 5 + esInfoLength
        }

        if !discovered.isEmpty {
            streams = discovered
        }
    }

    // MARK: PES assembly

    /// A PES payload runs from one payload-unit-start to the next, so a new start
    /// both emits the previous unit and begins the next.
    private func assemble(pid: UInt16,
                          streamType: ElementaryStreamType,
                          payload: Data,
                          payloadUnitStart: Bool) -> AccessUnit? {

        var completed: AccessUnit?

        if payloadUnitStart {

            if let previous = pending[pid] {
                completed = makeAccessUnit(pid: pid, streamType: streamType, pes: previous)
            }

            pending[pid] = payload

        } else {

            guard pending[pid] != nil else { return nil }
            pending[pid]?.append(payload)

        }

        return completed
    }

    /// Parses the PES header off the front and returns the elementary bytes.
    private func makeAccessUnit(pid: UInt16, streamType: ElementaryStreamType, pes: Data) -> AccessUnit? {

        let bytes = [UInt8](pes)

        /// packet_start_code_prefix is 0x000001.
        guard bytes.count >= 9,
              bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01 else {
            return nil
        }

        let flags = bytes[7]
        let headerLength = Int(bytes[8])
        let payloadStart = 9 + headerLength

        guard payloadStart <= bytes.count else { return nil }

        var pts: UInt64?
        var dts: UInt64?

        let hasPts = flags & 0x80 != 0
        let hasDts = flags & 0x40 != 0

        if hasPts, bytes.count >= 14 {
            pts = Self.readTimeStamp(bytes, at: 9)
        }

        if hasPts, hasDts, bytes.count >= 19 {
            dts = Self.readTimeStamp(bytes, at: 14)
        }

        return AccessUnit(
            pid: pid,
            streamType: streamType,
            presentationTimeStamp: pts,
            decodeTimeStamp: dts,
            data: Data(bytes[payloadStart...])
        )
    }

    /// A PES timestamp is 33 bits split across five bytes with marker bits between.
    private static func readTimeStamp(_ bytes: [UInt8], at offset: Int) -> UInt64? {

        guard offset + 5 <= bytes.count else { return nil }

        let b0 = UInt64(bytes[offset])
        let b1 = UInt64(bytes[offset + 1])
        let b2 = UInt64(bytes[offset + 2])
        let b3 = UInt64(bytes[offset + 3])
        let b4 = UInt64(bytes[offset + 4])

        return ((b0 & 0x0E) << 29)
             | (b1 << 22)
             | ((b2 & 0xFE) << 14)
             | (b3 << 7)
             | ((b4 & 0xFE) >> 1)
    }
}
