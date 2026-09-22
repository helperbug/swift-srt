import XCTest
@testable import SwiftSrt

/// Covers the hardening classes libsrt addressed in 1.5.7, checked against this
/// implementation: KM length validation, minimum MSS, DROPREQ range validation,
/// ACK validation, and handshake state rollback from late or forged packets.
final class HardeningTests: XCTestCase {

    private let peerIp = "10.0.0.9"

    // MARK: Handshake state rollback

    /// A duplicate or replayed conclusion request must not crash an established
    /// listener, and must not roll it back out of the active state.
    func testLateConclusionRequestDoesNotDisturbActiveListener() throws {
        let synCookie: UInt32 = 0x1A2B3C4D

        let listener = SrtListenerContext(
            srtSocketID: 0x0A0B0C0D,
            peerSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: synCookie,
            peerIpAddress: peerIp.ipStringToData!,
            encrypted: false
        )

        _ = listener.start()

        let conclusion = SrtHandshake.makeConclusionRequest(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: synCookie,
            peerIpAddress: peerIp.ipStringToData!,
            extensions: [.handshakeRequest: hsreq()]
        )

        let first = listener.handleHandshake(handshake: conclusion)
        XCTAssertEqual(listener.state, .active)
        XCTAssertEqual(first.sockets.count, 1)

        // A replay of the same packet must be absorbed, not acted on twice.
        let replay = listener.handleHandshake(handshake: conclusion) + listener.handleHandshake(handshake: conclusion)

        XCTAssertEqual(listener.state, .active, "an established listener must not roll back")
        XCTAssertTrue(replay.sockets.isEmpty, "a replayed conclusion must not create a second socket")
    }

    /// A late induction request arriving after the connection is up must not
    /// restart the handshake.
    func testLateInductionRequestDoesNotRollBackListener() throws {
        let synCookie: UInt32 = 0x1A2B3C4D

        let listener = SrtListenerContext(
            srtSocketID: 0x0A0B0C0D,
            peerSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: synCookie,
            peerIpAddress: peerIp.ipStringToData!,
            encrypted: false
        )

        _ = listener.start()
        let established = listener.handleHandshake(handshake: SrtHandshake.makeConclusionRequest(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: synCookie,
            peerIpAddress: peerIp.ipStringToData!,
            extensions: [.handshakeRequest: hsreq()]
        ))

        XCTAssertEqual(listener.state, .active)
        XCTAssertEqual(established.sockets.count, 1)

        let late = listener.handleHandshake(handshake: SrtHandshake.makeInductionRequest(
            srtSocketID: 0x11223344,
            serverIpAddress: peerIp.ipStringToData!
        ))

        XCTAssertEqual(listener.state, .active, "a late induction must not reopen the handshake")
        XCTAssertTrue(late.sockets.isEmpty)
    }

    /// The caller must likewise absorb a duplicated conclusion response.
    func testLateConclusionResponseDoesNotDisturbActiveCaller() throws {
        let caller = SrtCallerContext(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            encrypted: false
        )

        _ = caller.start()

        _ = caller.handleHandshake(handshake: SrtHandshake.makeInductionResponse(
            srtSocketID: 0x0A0B0C0D,
            initialPacketSequenceNumber: 0,
            synCookie: 0x1A2B3C4D,
            peerIpAddress: "10.0.0.1".ipStringToData!
        ))

        let response = SrtHandshake.makeConclusionResponse(
            srtSocketID: 0x0A0B0C0D,
            initialPacketSequenceNumber: 0,
            synCookie: 0,
            peerIpAddress: "10.0.0.1".ipStringToData!
        )

        let first = caller.handleHandshake(handshake: response)
        XCTAssertEqual(caller.state, .active)
        XCTAssertEqual(first.sockets.count, 1)

        let replay = caller.handleHandshake(handshake: response)

        XCTAssertEqual(caller.state, .active, "an established caller must not roll back")
        XCTAssertTrue(replay.sockets.isEmpty, "a replayed response must not create a second socket")
    }

    /// libsrt's induction response carries the caller's own ID in the SRT Socket
    /// ID field; the listener's real ID arrives with the conclusion response and
    /// must be the one the socket addresses.
    func testCallerTakesPeerIdFromConclusionResponse() throws {
        let caller = SrtCallerContext(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            encrypted: false
        )

        _ = caller.start()

        _ = caller.handleHandshake(handshake: SrtHandshake.makeInductionResponse(
            srtSocketID: 0x11223344, // libsrt echoes the caller's ID here
            initialPacketSequenceNumber: 0,
            synCookie: 0x1A2B3C4D,
            peerIpAddress: "10.0.0.1".ipStringToData!
        ))

        let established = caller.handleHandshake(handshake: SrtHandshake.makeConclusionResponse(
            srtSocketID: 0x0A0B0C0D, // the accepted socket's real ID
            initialPacketSequenceNumber: 0,
            synCookie: 0,
            peerIpAddress: "10.0.0.1".ipStringToData!
        ))

        let socket = try XCTUnwrap(established.sockets.first)
        XCTAssertEqual(socket.socketId, 0x11223344)
        XCTAssertEqual(socket.peerSocketId, 0x0A0B0C0D, "replies must go to the accepted socket, not to ourselves")
    }

    // MARK: Minimum MSS

    /// An undersized MTU would size payload buffers to nothing. Reject it at the
    /// handshake rather than carrying it into buffer allocation.
    func testUndersizedMtuIsRejected() throws {
        for mtu: UInt32 in [0, 1, 63, SrtHandshake.minimumTransmissionUnitSize - 1] {
            let handshake = SrtHandshake(
                hsVersion: .version5,
                encryptionField: 0,
                extensionField: 1,
                initialPacketSequenceNumber: 1,
                maximumTransmissionUnitSize: mtu,
                maximumFlowWindowSize: 8192,
                handshakeType: .conclusion,
                srtSocketID: 0x11223344,
                synCookie: 1,
                peerIPAddress: peerIp.ipStringToData!,
                extensionType: .none,
                extensionLength: 0,
                extensionContents: Data()
            )

            XCTAssertFalse(handshake.hasUsableTransmissionParameters, "MTU \(mtu) must be rejected")
        }
    }

    func testTypicalMtuIsAccepted() throws {
        let handshake = SrtHandshake.makeConclusionRequest(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 1,
            synCookie: 1,
            peerIpAddress: peerIp.ipStringToData!,
            extensions: [.handshakeRequest: hsreq()]
        )

        XCTAssertTrue(handshake.hasUsableTransmissionParameters)
    }

    /// A listener must not establish a connection on an unusable MTU.
    func testListenerRejectsUndersizedMtu() throws {
        let synCookie: UInt32 = 0x1A2B3C4D

        let listener = SrtListenerContext(
            srtSocketID: 0x0A0B0C0D,
            peerSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: synCookie,
            peerIpAddress: peerIp.ipStringToData!,
            encrypted: false
        )

        _ = listener.start()

        let outcome = listener.handleHandshake(handshake: SrtHandshake(
            hsVersion: .version5,
            encryptionField: 0,
            extensionField: 1,
            initialPacketSequenceNumber: 0,
            maximumTransmissionUnitSize: 16, // far below a usable payload
            maximumFlowWindowSize: 8192,
            handshakeType: .conclusion,
            srtSocketID: 0x11223344,
            synCookie: synCookie,
            peerIPAddress: peerIp.ipStringToData!,
            extensionType: .none,
            extensionLength: 0,
            extensionContents: Data(),
            extensions: [.handshakeRequest: hsreq()]
        ))

        XCTAssertTrue(outcome.sockets.isEmpty, "an unusable MTU must not establish a connection")
    }

    // MARK: Key material length validation

    /// Every KM length is peer supplied. None of them may drive an unchecked read.
    func testKeyMaterialRejectsOversizedLengths() throws {
        // A 16 byte buffer that claims a 255-word salt and a 255-word key.
        var bytes = Data(repeating: 0, count: 16)
        bytes[13] = 0xFF // salt length in four-byte words
        bytes[14] = 0xFF // key length in four-byte words
        bytes[3] = 0x03  // KK = both keys

        XCTAssertNil(KeyMaterialFrame(bytes), "a KM message must not outrun its buffer")
    }

    func testKeyMaterialRejectsTruncatedBuffer() throws {
        for count in 0..<15 {
            XCTAssertNil(KeyMaterialFrame(Data(repeating: 0, count: count)), "count \(count)")
        }
    }

    /// Whatever a peer sends, reading the fields must not trap or over-read.
    func testKeyMaterialSurvivesArbitraryInput() throws {
        for seed in 0..<256 {
            var bytes = Data(repeating: UInt8(seed), count: 32)
            bytes[13] = UInt8(seed)
            bytes[14] = UInt8((seed &* 7) & 0xFF)

            if let frame = KeyMaterialFrame(bytes) {
                // Accessing every variable-length field must stay in bounds.
                XCTAssertLessThanOrEqual(frame.salt.count + frame.wrappedKey.count, bytes.count)
            }
        }
    }

    // MARK: DROPREQ ranges

    func testDropRequestRejectsReversedRange() throws {
        let reversed = makeDropRequest(first: 5000, last: 100)
        XCTAssertNil(MessageDropRequestFrame(reversed), "a reversed range must be rejected")
    }

    func testDropRequestRejectsImplausibleDistance() throws {
        let absurd = makeDropRequest(first: 0, last: 0x7FFFFFFE)
        XCTAssertNil(MessageDropRequestFrame(absurd), "an oversized range must be rejected")
    }

    func testDropRequestAcceptsOrderedRange() throws {
        let ordered = makeDropRequest(first: 100, last: 164)
        let frame = try XCTUnwrap(MessageDropRequestFrame(ordered))

        XCTAssertEqual(frame.firstSequenceNumber, 100)
        XCTAssertEqual(frame.lastSequenceNumber, 164)
    }

    // MARK: ACK validation

    func testAcknowledgementRejectsTruncatedBuffer() throws {
        for count in stride(from: 0, to: 44, by: 4) {
            XCTAssertNil(AcknowledgementFrame(Data(repeating: 0, count: count)), "count \(count)")
        }
    }

    /// A sequence number with the top bit set is out of the valid 31-bit range.
    func testAcknowledgementRejectsOutOfRangeSequenceNumber() throws {
        var bytes = Data(repeating: 0, count: 44)
        bytes[0] = 0x80
        bytes[1] = 0x02 // acknowledgement control type
        // Last acknowledged packet sequence number, bytes 16..20, top bit set.
        bytes[16] = 0xFF
        bytes[17] = 0xFF
        bytes[18] = 0xFF
        bytes[19] = 0xFF

        XCTAssertNil(AcknowledgementFrame(bytes), "a 32-bit sequence number is out of range")
    }

    // MARK: Helpers

    private func hsreq() -> Data {
        HandshakeExtensionMessage(
            srtVersion: SrtHandshake.srtLibraryVersion,
            srtFlags: SrtHandshake.defaultSrtFlags,
            receiverTsbpdDelay: 120,
            senderTsbpdDelay: 120
        ).data
    }

    private func makeDropRequest(first: UInt32, last: UInt32) -> Data {
        var bytes = Data(capacity: 24)
        bytes.append(contentsOf: (UInt16(0x8000 | 7)).bytes) // control bit + DROPREQ
        bytes.append(contentsOf: UInt16(0).bytes)
        bytes.append(contentsOf: UInt32(1).bytes)  // message number
        bytes.append(contentsOf: UInt32(0).bytes)  // timestamp
        bytes.append(contentsOf: UInt32(0xAABBCCDD).bytes)
        bytes.append(contentsOf: first.bytes)
        bytes.append(contentsOf: last.bytes)
        return bytes
    }
}
