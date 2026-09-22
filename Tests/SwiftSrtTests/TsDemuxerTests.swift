import XCTest
@testable import SwiftSrtMedia

/// Exercises the demuxer against synthetic transport packets, so the expected
/// values are known exactly rather than inferred from a capture.
final class TsDemuxerTests: XCTestCase {

    private let videoPid: UInt16 = 0x0100
    private let pmtPid: UInt16 = 0x1000

    // MARK: Packet construction helpers

    /// Builds one 188-byte transport packet with the given payload, padding with
    /// an adaptation field when the payload is short.
    private func makePacket(pid: UInt16,
                            payloadUnitStart: Bool,
                            continuityCounter: UInt8,
                            payload: Data) -> Data {

        var packet = Data()
        packet.append(0x47)
        packet.append(UInt8((payloadUnitStart ? 0x40 : 0x00) | UInt8(pid >> 8) & 0x1F))
        packet.append(UInt8(pid & 0xFF))

        let room = TsDemuxer.packetSize - 4
        let stuffing = room - payload.count

        if stuffing > 0 {
            // Adaptation field present, then payload.
            packet.append(0x30 | (continuityCounter & 0x0F))
            packet.append(UInt8(stuffing - 1))
            if stuffing >= 2 {
                packet.append(0x00) // no adaptation flags
                packet.append(contentsOf: repeatElement(UInt8(0xFF), count: stuffing - 2))
            }
        } else {
            packet.append(0x10 | (continuityCounter & 0x0F))
        }

        packet.append(payload)

        XCTAssertEqual(packet.count, TsDemuxer.packetSize, "packet must be exactly 188 bytes")

        return packet
    }

    /// A PAT pointing at one program carried on `pmtPid`.
    private func makePat(continuityCounter: UInt8) -> Data {
        var section = Data()
        section.append(0x00)                       // table_id
        section.append(contentsOf: [0xB0, 0x0D])   // section_syntax + length 13
        section.append(contentsOf: [0x00, 0x01])   // transport_stream_id
        section.append(0xC1)                       // version, current
        section.append(0x00)                       // section_number
        section.append(0x00)                       // last_section_number
        section.append(contentsOf: [0x00, 0x01])   // program_number 1
        section.append(UInt8(0xE0 | UInt8(pmtPid >> 8)))
        section.append(UInt8(pmtPid & 0xFF))
        section.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // CRC placeholder

        var payload = Data([0x00]) // pointer_field
        payload.append(section)

        return makePacket(pid: 0x0000, payloadUnitStart: true, continuityCounter: continuityCounter, payload: payload)
    }

    /// A PMT declaring one H.264 stream on `videoPid`.
    private func makePmt(continuityCounter: UInt8) -> Data {
        var section = Data()
        section.append(0x02)                       // table_id
        section.append(contentsOf: [0xB0, 0x12])   // section_syntax + length 18
        section.append(contentsOf: [0x00, 0x01])   // program_number
        section.append(0xC1)
        section.append(0x00)
        section.append(0x00)
        section.append(UInt8(0xE0 | UInt8(videoPid >> 8))) // PCR PID
        section.append(UInt8(videoPid & 0xFF))
        section.append(contentsOf: [0xF0, 0x00])   // program_info_length 0
        section.append(ElementaryStreamType.h264.rawValue)
        section.append(UInt8(0xE0 | UInt8(videoPid >> 8)))
        section.append(UInt8(videoPid & 0xFF))
        section.append(contentsOf: [0xF0, 0x00])   // ES_info_length 0
        section.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // CRC placeholder

        var payload = Data([0x00])
        payload.append(section)

        return makePacket(pid: pmtPid, payloadUnitStart: true, continuityCounter: continuityCounter, payload: payload)
    }

    /// A PES packet carrying `elementary` with an optional PTS.
    private func makePes(elementary: Data, pts: UInt64?) -> Data {
        var pes = Data()
        pes.append(contentsOf: [0x00, 0x00, 0x01]) // start code prefix
        pes.append(0xE0)                           // stream_id: video

        let headerDataLength = pts == nil ? 0 : 5
        let packetLength = 3 + headerDataLength + elementary.count

        pes.append(UInt8((packetLength >> 8) & 0xFF))
        pes.append(UInt8(packetLength & 0xFF))
        pes.append(0x80)                           // marker bits
        pes.append(pts == nil ? 0x00 : 0x80)       // PTS present flag
        pes.append(UInt8(headerDataLength))

        if let pts {
            pes.append(UInt8(0x21 | ((pts >> 29) & 0x0E)))
            pes.append(UInt8((pts >> 22) & 0xFF))
            pes.append(UInt8(0x01 | ((pts >> 14) & 0xFE)))
            pes.append(UInt8((pts >> 7) & 0xFF))
            pes.append(UInt8(0x01 | ((pts << 1) & 0xFE)))
        }

        pes.append(elementary)

        return pes
    }

    // MARK: Tests

    func testDiscoversStreamsFromProgramTables() throws {
        let demuxer = TsDemuxer()

        _ = demuxer.append(makePat(continuityCounter: 0))
        _ = demuxer.append(makePmt(continuityCounter: 0))

        XCTAssertEqual(demuxer.streams[videoPid], .h264)
    }

    func testExtractsAccessUnitWithTimestamp() throws {
        let demuxer = TsDemuxer()

        _ = demuxer.append(makePat(continuityCounter: 0))
        _ = demuxer.append(makePmt(continuityCounter: 0))

        let elementary = Data((0..<32).map { UInt8($0) })
        let pes = makePes(elementary: elementary, pts: 900_000)

        _ = demuxer.append(makePacket(pid: videoPid, payloadUnitStart: true, continuityCounter: 0, payload: pes))

        // The unit is only complete once the next one starts, or on flush.
        let units = demuxer.flush()

        XCTAssertEqual(units.count, 1)
        let unit = try XCTUnwrap(units.first)
        XCTAssertEqual(unit.pid, videoPid)
        XCTAssertEqual(unit.streamType, .h264)
        XCTAssertEqual(unit.presentationTimeStamp, 900_000)
        XCTAssertEqual(unit.data, elementary)
    }

    /// A PES payload spanning several transport packets must reassemble in order.
    func testReassemblesAcrossPackets() throws {
        let demuxer = TsDemuxer()

        _ = demuxer.append(makePat(continuityCounter: 0))
        _ = demuxer.append(makePmt(continuityCounter: 0))

        let elementary = Data((0..<400).map { UInt8($0 % 251) })
        let pes = makePes(elementary: elementary, pts: 450_000)

        // Split the PES across packets of at most 184 payload bytes.
        var offset = 0
        var counter: UInt8 = 0
        var first = true

        while offset < pes.count {
            let take = min(184, pes.count - offset)
            let slice = pes.subdata(in: offset..<(offset + take))
            _ = demuxer.append(makePacket(pid: videoPid,
                                          payloadUnitStart: first,
                                          continuityCounter: counter,
                                          payload: slice))
            offset += take
            counter = (counter &+ 1) & 0x0F
            first = false
        }

        let units = demuxer.flush()

        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units.first?.data, elementary, "payload must reassemble byte for byte")
        XCTAssertEqual(units.first?.presentationTimeStamp, 450_000)
    }

    /// A gap in the continuity counter means loss; the partial unit is unusable.
    func testContinuityGapDropsPartialUnit() throws {
        let demuxer = TsDemuxer()

        _ = demuxer.append(makePat(continuityCounter: 0))
        _ = demuxer.append(makePmt(continuityCounter: 0))

        let elementary = Data(repeating: 0xAB, count: 400)
        let pes = makePes(elementary: elementary, pts: 1000)

        _ = demuxer.append(makePacket(pid: videoPid, payloadUnitStart: true, continuityCounter: 0, payload: pes.prefix(184)))
        // Counter jumps from 0 to 5: three packets went missing.
        _ = demuxer.append(makePacket(pid: videoPid, payloadUnitStart: false, continuityCounter: 5, payload: Data(pes.dropFirst(184).prefix(184))))

        XCTAssertEqual(demuxer.discontinuities, 1)
        XCTAssertTrue(demuxer.flush().isEmpty, "a unit with a hole in it must not be emitted")
    }

    /// The demuxer must recover if it is handed a stream that is not aligned.
    func testResynchronisesOnMisalignedStream() throws {
        let demuxer = TsDemuxer()

        var stream = Data([0x11, 0x22, 0x33]) // junk ahead of the first sync byte
        stream.append(makePat(continuityCounter: 0))
        stream.append(makePmt(continuityCounter: 0))

        _ = demuxer.append(stream)

        XCTAssertEqual(demuxer.streams[videoPid], .h264, "must resync and still read the tables")
    }

    /// Feeding the stream one byte at a time must produce the same result.
    func testHandlesArbitraryChunkBoundaries() throws {
        let demuxer = TsDemuxer()

        var stream = Data()
        stream.append(makePat(continuityCounter: 0))
        stream.append(makePmt(continuityCounter: 0))

        let elementary = Data((0..<100).map { UInt8($0) })
        stream.append(makePacket(pid: videoPid,
                                 payloadUnitStart: true,
                                 continuityCounter: 0,
                                 payload: makePes(elementary: elementary, pts: 90_000)))

        for byte in stream {
            _ = demuxer.append(Data([byte]))
        }

        let units = demuxer.flush()
        XCTAssertEqual(units.first?.data, elementary)
    }
}
