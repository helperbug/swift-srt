import XCTest
@testable import SwiftSrt

/// The second word of a data packet header packs five fields:
/// PP (bits 31-30), O (29), KK (28-27), R (26), message number (25-0).
final class DataPacketWireFormatTests: XCTestCase {

    private func makePacket(
        packetPosition: UInt8 = 0b11,
        orderFlag: Bool = false,
        encryptionFlags: UInt8 = 0,
        retransmittedFlag: Bool = false,
        messageNumber: UInt32 = 1
    ) -> DataPacketFrame {
        DataPacketFrame(
            packetSequenceNumber: 0x0000BEEF,
            packetPosition: packetPosition,
            orderFlag: orderFlag,
            encryptionFlags: encryptionFlags,
            retransmittedFlag: retransmittedFlag,
            messageNumber: messageNumber,
            timestamp: 0x11223344,
            destinationSocketID: 0xAABBCCDD,
            payload: Data([1, 2, 3, 4]),
            authenticationTag: Data()
        )
    }

    func testHeaderFieldsRoundTrip() throws {
        let packet = makePacket(
            packetPosition: 0b10,
            orderFlag: true,
            encryptionFlags: 0b01,
            retransmittedFlag: true,
            messageNumber: 0x000ABCDE
        )

        let decoded = try XCTUnwrap(DataPacketFrame(packet.data))

        XCTAssertTrue(decoded.isData)
        XCTAssertEqual(decoded.packetSequenceNumber, 0x0000BEEF)
        XCTAssertEqual(decoded.packetPosition, 0b10)
        XCTAssertTrue(decoded.orderFlag)
        XCTAssertEqual(decoded.encryptionFlags, 0b01)
        XCTAssertTrue(decoded.retransmittedFlag)
        XCTAssertEqual(decoded.messageNumber, 0x000ABCDE)
        XCTAssertEqual(decoded.timestamp, 0x11223344)
        XCTAssertEqual(decoded.destinationSocketID, 0xAABBCCDD)
    }

    /// Each flag must land in its own bit; setting one must not disturb the others.
    func testFlagsAreIndependent() throws {
        let plain = try XCTUnwrap(DataPacketFrame(makePacket().data))
        XCTAssertFalse(plain.orderFlag)
        XCTAssertFalse(plain.retransmittedFlag)
        XCTAssertEqual(plain.encryptionFlags, 0)
        XCTAssertEqual(plain.messageNumber, 1)

        let ordered = try XCTUnwrap(DataPacketFrame(makePacket(orderFlag: true).data))
        XCTAssertTrue(ordered.orderFlag)
        XCTAssertFalse(ordered.retransmittedFlag)
        XCTAssertEqual(ordered.encryptionFlags, 0)
        XCTAssertEqual(ordered.messageNumber, 1, "the order flag must not corrupt the message number")

        let retransmitted = try XCTUnwrap(DataPacketFrame(makePacket(retransmittedFlag: true).data))
        XCTAssertTrue(retransmitted.retransmittedFlag)
        XCTAssertFalse(retransmitted.orderFlag)
        XCTAssertEqual(retransmitted.messageNumber, 1)

        let encrypted = try XCTUnwrap(DataPacketFrame(makePacket(encryptionFlags: 0b10).data))
        XCTAssertEqual(encrypted.encryptionFlags, 0b10)
        XCTAssertFalse(encrypted.orderFlag)
        XCTAssertEqual(encrypted.messageNumber, 1)
    }

    /// A data packet's first word is its sequence number, with the top bit clear.
    func testDataPacketIsNotMistakenForControl() throws {
        let packet = makePacket()

        XCTAssertEqual(packet.data[0] & 0x80, 0, "a data packet must leave the top bit clear")

        let asSrtPacket = SrtPacket(data: packet.data)
        XCTAssertTrue(asSrtPacket.isData)
    }

    func testPayloadRoundTrips() throws {
        let decoded = try XCTUnwrap(DataPacketFrame(makePacket().data))
        XCTAssertEqual(decoded.payload, Data([1, 2, 3, 4]))
    }

    /// Stream IDs are word-reversed on the wire, so every length up to a word
    /// boundary has to survive the round trip.
    func testStreamIdRoundTripsAtEveryLength() throws {
        for length in 1...20 {
            let streamId = String(repeating: "a", count: length - 1) + "z"

            let handshake = SrtHandshake.makeConclusionRequest(
                srtSocketID: 1,
                initialPacketSequenceNumber: 0,
                synCookie: 1,
                peerIpAddress: "10.0.0.1".ipStringToData!,
                extensions: [.streamId: StrCallerInductedState.encodeStreamId(streamId)]
            )

            let decoded = try XCTUnwrap(SrtHandshake(data: handshake.data))
            XCTAssertEqual(decoded.streamId, streamId, "length \(length)")
        }
    }
}
