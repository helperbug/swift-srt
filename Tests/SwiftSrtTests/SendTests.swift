import XCTest
@testable import SwiftSrt

final class SendBufferTests: XCTestCase {

    private func packet(_ sequence: UInt32, message: UInt32 = 1, timestamp: UInt32 = 0) -> DataPacketFrame {
        DataPacketFrame(packetSequenceNumber: sequence, packetPosition: 0b11, orderFlag: false,
                        encryptionFlags: 0, retransmittedFlag: false, messageNumber: message,
                        timestamp: timestamp, destinationSocketID: 1, payload: Data([1, 2, 3]), authenticationTag: Data())
    }

    func testAllocationAdvancesSequenceAndMessage() {
        var buffer = SendBuffer(initialSequence: SrtSequence.maximum)
        let a = buffer.allocate(message: true)
        let b = buffer.allocate(message: false)
        let c = buffer.allocate(message: true)
        XCTAssertEqual(a.sequence, SrtSequence.maximum)
        XCTAssertEqual(b.sequence, 0, "wraps")
        XCTAssertEqual(c.sequence, 1)
        XCTAssertEqual(a.message, 1, "first message")
        XCTAssertEqual(b.message, 2, "not starting a message leaves the counter where it is")
        XCTAssertEqual(c.message, 2, "so the next message takes it")
    }

    func testAcknowledgeReleases() {
        var buffer = SendBuffer(initialSequence: 10)
        for i in 10..<15 { buffer.store(packet(UInt32(i)), sent: 0) }
        XCTAssertEqual(buffer.count, 5)
        buffer.acknowledge(upTo: 13)
        XCTAssertEqual(buffer.count, 2, "13 and 14 still held")
        XCTAssertEqual(buffer.oldest, 13)
        XCTAssertEqual(buffer.statistics.acknowledged, 3)
        buffer.acknowledge(upTo: 15)
        XCTAssertNil(buffer.oldest)
    }

    func testRetransmissionSetsFlagAndCounts() {
        var buffer = SendBuffer(initialSequence: 1)
        buffer.store(packet(1), sent: 0)
        let again = buffer.retransmission(of: 1)
        XCTAssertNotNil(again)
        XCTAssertTrue(again!.retransmittedFlag)
        XCTAssertEqual(again!.packetSequenceNumber, 1)
        XCTAssertNil(buffer.retransmission(of: 2), "never sent")
        XCTAssertEqual(buffer.statistics.retransmitted, 1)
        XCTAssertEqual(buffer.statistics.nakReferencesUnknown, 1)
    }

    func testTooLateDropGroupsRanges() {
        var buffer = SendBuffer(initialSequence: 1)
        buffer.store(packet(1, message: 1), sent: 0)
        buffer.store(packet(2, message: 1), sent: 0)
        buffer.store(packet(3, message: 2), sent: 0)
        buffer.store(packet(4, message: 3), sent: 500_000)

        // 1-3 are 600ms old, 4 is 100ms old; the budget is 200ms.
        let dropped = buffer.dropExpired(now: 600_000, latencyMicroseconds: 200_000)
        XCTAssertEqual(dropped.map { [$0.first, $0.last, $0.message] }, [[1, 2, 1], [3, 3, 2]], "grouped by message")
        XCTAssertEqual(buffer.count, 1, "4 is recent")
        XCTAssertEqual(buffer.oldest, 4)
        XCTAssertEqual(buffer.statistics.dropped, 3)
    }
}
