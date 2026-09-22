import XCTest
@testable import SwiftSrt

final class SrtSequenceTests: XCTestCase {

    func testCompareAcrossWrap() {
        XCTAssertEqual(SrtSequence.compare(5, 3), 1)
        XCTAssertEqual(SrtSequence.compare(3, 5), -1)
        XCTAssertEqual(SrtSequence.compare(7, 7), 0)
        // 0 comes right after the maximum.
        XCTAssertEqual(SrtSequence.compare(0, SrtSequence.maximum), 1)
        XCTAssertEqual(SrtSequence.compare(SrtSequence.maximum, 0), -1)
    }

    func testOffsetAndLengthAcrossWrap() {
        XCTAssertEqual(SrtSequence.offset(from: 10, to: 15), 5)
        XCTAssertEqual(SrtSequence.offset(from: 15, to: 10), -5)
        XCTAssertEqual(SrtSequence.offset(from: SrtSequence.maximum, to: 2), 3)
        XCTAssertEqual(SrtSequence.length(from: SrtSequence.maximum - 1, to: 1), 4)
        XCTAssertEqual(SrtSequence.length(from: 5, to: 3), 0)
    }

    func testIncrementWraps() {
        XCTAssertEqual(SrtSequence.increment(SrtSequence.maximum), 0)
        XCTAssertEqual(SrtSequence.decrement(0), SrtSequence.maximum)
        XCTAssertEqual(SrtSequence.increment(10, by: -3), 7)
    }

    func testTimeIsBeforeWraps() {
        XCTAssertTrue(SrtSequence.timeIsBefore(100, 200))
        XCTAssertFalse(SrtSequence.timeIsBefore(200, 100))
        XCTAssertTrue(SrtSequence.timeIsBefore(UInt32.max - 10, 5), "the clock wrapped; 5 is later")
    }
}

final class RttEstimatorTests: XCTestCase {

    func testFirstSampleSeeds() {
        var rtt = RttEstimator()
        rtt.add(sample: 40_000)
        XCTAssertEqual(rtt.rtt, 40_000)
        XCTAssertEqual(rtt.variance, 20_000)
    }

    func testSmoothing() {
        var rtt = RttEstimator()
        rtt.add(sample: 40_000)
        rtt.add(sample: 80_000)
        XCTAssertEqual(rtt.rtt, (40_000 * 7 + 80_000) / 8)
        XCTAssertEqual(rtt.variance, (20_000 * 3 + 40_000) / 4)
    }

    func testNakIntervalFloor() {
        var rtt = RttEstimator()
        rtt.add(sample: 1_000)
        XCTAssertEqual(rtt.nakInterval, 20_000)
    }
}

final class ReceiveBufferTests: XCTestCase {

    private func packet(_ sequence: UInt32, timestamp: UInt32 = 0, retransmitted: Bool = false) -> DataPacketFrame {
        DataPacketFrame(packetSequenceNumber: sequence, packetPosition: 0b11, orderFlag: false,
                        encryptionFlags: 0, retransmittedFlag: retransmitted, messageNumber: sequence,
                        timestamp: timestamp, destinationSocketID: 1, payload: Data([UInt8(sequence & 0xFF)]),
                        authenticationTag: Data())
    }

    func testInOrderDeliversImmediatelyWithoutLatency() {
        var buffer = ReceiveBuffer(initialSequence: 100, latencyMicroseconds: 0)
        XCTAssertEqual(buffer.insert(packet(100), arrival: 0), .stored)
        XCTAssertEqual(buffer.insert(packet(101), arrival: 0), .stored)
        let out = buffer.drain(now: 0)
        XCTAssertEqual(out.map(\.packetSequenceNumber), [100, 101])
        XCTAssertEqual(buffer.deliveryPoint, 102)
        XCTAssertTrue(buffer.lossList.isEmpty)
    }

    func testGapOpensLossAndHoldsDelivery() {
        var buffer = ReceiveBuffer(initialSequence: 100, latencyMicroseconds: 0)
        _ = buffer.insert(packet(100), arrival: 0)
        _ = buffer.insert(packet(103), arrival: 0)

        XCTAssertEqual(buffer.lossList, [.init(first: 101, last: 102, reported: 0)])
        XCTAssertEqual(buffer.statistics.lost, 2)
        XCTAssertEqual(buffer.drain(now: 0).map(\.packetSequenceNumber), [100], "must stop at the hole")
        XCTAssertEqual(buffer.acknowledgeSequence, 101)
    }

    func testFillingTheHoleSplitsAndClearsLoss() {
        var buffer = ReceiveBuffer(initialSequence: 100, latencyMicroseconds: 0)
        _ = buffer.insert(packet(100), arrival: 0)
        _ = buffer.insert(packet(105), arrival: 0)       // loses 101...104
        _ = buffer.insert(packet(103, retransmitted: true), arrival: 0)

        XCTAssertEqual(buffer.lossList, [.init(first: 101, last: 102, reported: 0), .init(first: 104, last: 104, reported: 0)])
        XCTAssertEqual(buffer.statistics.retransmitted, 1)

        _ = buffer.insert(packet(101), arrival: 0)
        _ = buffer.insert(packet(102), arrival: 0)
        _ = buffer.insert(packet(104), arrival: 0)
        XCTAssertTrue(buffer.lossList.isEmpty)
        XCTAssertEqual(buffer.drain(now: 0).map(\.packetSequenceNumber), [100, 101, 102, 103, 104, 105])
    }

    func testDuplicateAndBelatedAreCounted() {
        var buffer = ReceiveBuffer(initialSequence: 100, latencyMicroseconds: 0)
        _ = buffer.insert(packet(100), arrival: 0)
        XCTAssertEqual(buffer.insert(packet(100), arrival: 0), .duplicate)
        _ = buffer.drain(now: 0)
        XCTAssertEqual(buffer.insert(packet(99), arrival: 0), .belated)
        XCTAssertEqual(buffer.insert(packet(100), arrival: 0), .belated, "already delivered")
        XCTAssertEqual(buffer.statistics.duplicates, 1)
        XCTAssertEqual(buffer.statistics.belated, 2)
    }

    func testTsbpdHoldsUntilDue() {
        // 100ms latency; peer timestamps in microseconds.
        var buffer = ReceiveBuffer(initialSequence: 1, latencyMicroseconds: 100_000)
        _ = buffer.insert(packet(1, timestamp: 0), arrival: 1_000_000)
        _ = buffer.insert(packet(2, timestamp: 33_000), arrival: 1_033_000)

        XCTAssertTrue(buffer.drain(now: 1_050_000).isEmpty, "first packet is due at arrival + latency")
        XCTAssertEqual(buffer.drain(now: 1_100_000).map(\.packetSequenceNumber), [1])
        XCTAssertTrue(buffer.drain(now: 1_120_000).isEmpty)
        XCTAssertEqual(buffer.drain(now: 1_133_000).map(\.packetSequenceNumber), [2])
    }

    func testTooLateDropSkipsTheHole() {
        var buffer = ReceiveBuffer(initialSequence: 1, latencyMicroseconds: 100_000)
        _ = buffer.insert(packet(1, timestamp: 0), arrival: 1_000_000)
        _ = buffer.insert(packet(3, timestamp: 66_000), arrival: 1_066_000)   // 2 is missing
        _ = buffer.drain(now: 1_100_000)                                        // delivers 1

        XCTAssertEqual(buffer.dropExpired(now: 1_150_000), 0, "3 is not yet due, keep waiting for 2")
        XCTAssertEqual(buffer.dropExpired(now: 1_166_000), 1, "3 is due; give up on 2")
        XCTAssertEqual(buffer.deliveryPoint, 3)
        XCTAssertTrue(buffer.lossList.isEmpty)
        XCTAssertEqual(buffer.statistics.dropped, 1)
        XCTAssertEqual(buffer.drain(now: 1_166_000).map(\.packetSequenceNumber), [3])
    }

    func testLossReportPacing() {
        var buffer = ReceiveBuffer(initialSequence: 1, latencyMicroseconds: 0)
        _ = buffer.insert(packet(1), arrival: 0)
        _ = buffer.insert(packet(4), arrival: 0)

        XCTAssertEqual(buffer.lossesToReport(now: 1_000, interval: 20_000).count, 1, "new loss reports at once")
        XCTAssertTrue(buffer.lossesToReport(now: 5_000, interval: 20_000).isEmpty, "too soon to ask again")
        XCTAssertEqual(buffer.lossesToReport(now: 25_000, interval: 20_000).count, 1, "asks again after the interval")
    }

    func testDropRequestForgetsRange() {
        var buffer = ReceiveBuffer(initialSequence: 1, latencyMicroseconds: 0)
        _ = buffer.insert(packet(1), arrival: 0)
        _ = buffer.insert(packet(6), arrival: 0)
        _ = buffer.drain(now: 0)
        buffer.drop(from: 2, to: 5)
        XCTAssertTrue(buffer.lossList.isEmpty)
        XCTAssertEqual(buffer.deliveryPoint, 6)
        XCTAssertEqual(buffer.drain(now: 0).map(\.packetSequenceNumber), [6])
    }

    func testWrapAroundSequence() {
        var buffer = ReceiveBuffer(initialSequence: SrtSequence.maximum - 1, latencyMicroseconds: 0)
        _ = buffer.insert(packet(SrtSequence.maximum - 1), arrival: 0)
        _ = buffer.insert(packet(SrtSequence.maximum), arrival: 0)
        _ = buffer.insert(packet(0), arrival: 0)
        _ = buffer.insert(packet(1), arrival: 0)
        XCTAssertEqual(buffer.drain(now: 0).map(\.packetSequenceNumber), [SrtSequence.maximum - 1, SrtSequence.maximum, 0, 1])
        XCTAssertTrue(buffer.lossList.isEmpty)
    }
}

final class DriftTests: XCTestCase {

    private func packet(_ sequence: UInt32, timestamp: UInt32) -> DataPacketFrame {
        DataPacketFrame(packetSequenceNumber: sequence, packetPosition: 0b11, orderFlag: false,
                        encryptionFlags: 0, retransmittedFlag: false, messageNumber: sequence,
                        timestamp: timestamp, destinationSocketID: 1, payload: Data([1]), authenticationTag: Data())
    }

    /// The peer's clock runs 1% fast: after 1000 packets the arrival base
    /// shifts by the average error and the next delivery time reflects it.
    func testDriftFoldsIntoArrivalBase() {
        var buffer = ReceiveBuffer(initialSequence: 0, latencyMicroseconds: 100_000)

        for i in 0..<1001 {
            let peerTime = UInt32(i) * 10_000                 // peer says 10ms apart
            let arrival = 1_000_000 + UInt32(i) * 10_100      // they actually land 10.1ms apart
            _ = buffer.insert(packet(UInt32(i), timestamp: peerTime), arrival: arrival)
        }

        XCTAssertEqual(buffer.driftCorrections, 1)
        // Average error over 1000 samples of i*100µs is ~50ms.
        XCTAssertEqual(Double(buffer.driftMicroseconds), 50_000, accuracy: 200)

        let due = buffer.deliveryTime(of: packet(1001, timestamp: 1001 * 10_000))!
        let uncorrected: UInt32 = 1_000_000 + 1001 * 10_000 + 100_000
        XCTAssertEqual(Int(due) - Int(uncorrected), Int(buffer.driftMicroseconds), "delivery time moved by the drift")
    }

    func testRetransmissionsDoNotCountAsDrift() {
        var buffer = ReceiveBuffer(initialSequence: 0, latencyMicroseconds: 0)
        _ = buffer.insert(packet(0, timestamp: 0), arrival: 0)
        for i in 1..<1500 {
            let late = DataPacketFrame(packetSequenceNumber: UInt32(i), packetPosition: 0b11, orderFlag: false,
                                       encryptionFlags: 0, retransmittedFlag: true, messageNumber: UInt32(i),
                                       timestamp: UInt32(i) * 1000, destinationSocketID: 1, payload: Data([1]), authenticationTag: Data())
            _ = buffer.insert(late, arrival: UInt32(i) * 1000 + 500_000)
        }
        XCTAssertEqual(buffer.driftCorrections, 0, "retransmissions arrive late by definition; they must not skew the clock")
    }
}
