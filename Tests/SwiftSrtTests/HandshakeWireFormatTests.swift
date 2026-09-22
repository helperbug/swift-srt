import XCTest
@testable import SwiftSrt

/// Pins the on-the-wire handshake format against draft-sharabayko-mops-srt-01.
final class HandshakeWireFormatTests: XCTestCase {

    // MARK: Packet header

    /// Control packets set the MSB; the control type lives in bits 1..15.
    func testControlPacketHeaderLayout() throws {
        let packet = SrtPacket(
            field1: ControlTypes.shutdown.asField,
            socketID: 0x01020304,
            contents: Data()
        )

        XCTAssertEqual(packet.data.count, 16)
        XCTAssertFalse(packet.isData)
        XCTAssertEqual(packet.data[0], 0x80, "MSB must be set on a control packet")
        XCTAssertEqual(packet.data[1], 0x05, "Shutdown is control type 5")
        XCTAssertEqual(packet.destinationSocketID, 0x01020304)
    }

    /// `field1` must round-trip the full 31-bit field, not a truncated mask.
    /// `userDefined` is 0x7FFF, so it exercises every bit of the control type.
    func testControlPacketField1RoundTrips() throws {
        for controlType in [ControlTypes.shutdown, .keepAlive, .userDefined] {
            let packet = SrtPacket(
                field1: controlType.asField,
                socketID: 7,
                contents: Data()
            )

            XCTAssertEqual(packet.field1, controlType.asField, "\(controlType)")
        }
    }

    func testPacketHeaderDecodesControlFlag() throws {
        let packet = SrtPacket(field1: ControlTypes.keepAlive.asField, socketID: 9, contents: Data())

        packet.data.withUnsafeBytes { raw in
            let header = SrtPacketHeader(raw)
            XCTAssertTrue(header.isControl, "A packet with the MSB set is a control packet")
        }
    }

    // MARK: Handshake serialisation

    /// The fixed part of a handshake CIF is 48 bytes.
    func testHandshakeFixedSectionIs48Bytes() throws {
        let handshake = SrtHandshake.makeInductionRequest(
            srtSocketID: 0x11223344,
            serverIpAddress: "10.0.0.1".ipStringToData!
        )

        XCTAssertEqual(handshake.data.count, 48)
    }

    func testInductionRequestMatchesSpec() throws {
        let handshake = SrtHandshake.makeInductionRequest(
            srtSocketID: 0x11223344,
            serverIpAddress: "10.0.0.1".ipStringToData!
        )

        XCTAssertEqual(handshake.hsVersion, .version4)
        XCTAssertEqual(handshake.encryptionField, 0)
        XCTAssertEqual(handshake.extensionField, 2)
        XCTAssertEqual(handshake.handshakeType, .induction)
        XCTAssertEqual(handshake.synCookie, 0)
        XCTAssertTrue(handshake.isInductionRequest)
    }

    /// A handshake must survive encode -> decode unchanged.
    func testHandshakeRoundTripsThroughData() throws {
        let original = SrtHandshake.makeInductionRequest(
            srtSocketID: 0x11223344,
            serverIpAddress: "192.168.1.5".ipStringToData!
        )

        let decoded = try XCTUnwrap(SrtHandshake(data: original.data))

        XCTAssertEqual(decoded.hsVersion, original.hsVersion)
        XCTAssertEqual(decoded.encryptionField, original.encryptionField)
        XCTAssertEqual(decoded.extensionField, original.extensionField)
        XCTAssertEqual(decoded.initialPacketSequenceNumber, original.initialPacketSequenceNumber)
        XCTAssertEqual(decoded.maximumTransmissionUnitSize, original.maximumTransmissionUnitSize)
        XCTAssertEqual(decoded.maximumFlowWindowSize, original.maximumFlowWindowSize)
        XCTAssertEqual(decoded.handshakeType, original.handshakeType)
        XCTAssertEqual(decoded.srtSocketID, original.srtSocketID)
        XCTAssertEqual(decoded.synCookie, original.synCookie)
        XCTAssertEqual(decoded.peerIPAddress, original.peerIPAddress)
    }

    /// Extensions are TLVs: each one must carry its own type and length on the wire.
    func testConclusionRequestSerialisesExtensionHeaders() throws {
        let hsreq = HandshakeExtensionMessage(
            srtVersion: 0x00010502,
            srtFlags: 0xbf,
            receiverTsbpdDelay: 120,
            senderTsbpdDelay: 120
        )

        let handshake = SrtHandshake.makeConclusionRequest(
            srtSocketID: 0xAABBCCDD,
            initialPacketSequenceNumber: 1,
            synCookie: 0x12345678,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.handshakeRequest: hsreq.data]
        )

        let encoded = handshake.data

        // 48 byte fixed section + 4 byte TLV header + 12 byte HSREQ payload.
        XCTAssertEqual(encoded.count, 48 + 4 + 12)

        let typeField = UInt16(encoded[48]) << 8 | UInt16(encoded[49])
        let lengthField = UInt16(encoded[50]) << 8 | UInt16(encoded[51])

        XCTAssertEqual(typeField, HandshakeExtensionTypes.handshakeRequest.rawValue)
        XCTAssertEqual(lengthField, 3, "Length is counted in four-byte words")
    }

    /// Decoding the bytes we produced must recover the same extension payload.
    func testConclusionRequestExtensionsRoundTrip() throws {
        let hsreq = HandshakeExtensionMessage(
            srtVersion: 0x00010502,
            srtFlags: 0xbf,
            receiverTsbpdDelay: 120,
            senderTsbpdDelay: 80
        )

        let handshake = SrtHandshake.makeConclusionRequest(
            srtSocketID: 0xAABBCCDD,
            initialPacketSequenceNumber: 1,
            synCookie: 0x12345678,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.handshakeRequest: hsreq.data]
        )

        let decoded = try XCTUnwrap(SrtHandshake(data: handshake.data))

        XCTAssertEqual(decoded.srtVersion, 0x00010502)
        XCTAssertEqual(decoded.srtFlags, 0xbf)
        XCTAssertEqual(decoded.receiverTsbpdDelay, 120)
        XCTAssertEqual(decoded.senderTsbpdDelay, 80)
    }

    /// A truncated or hostile extension length must not read past the buffer.
    func testMalformedExtensionLengthIsRejected() throws {
        var bytes = SrtHandshake.makeInductionRequest(
            srtSocketID: 0x11223344,
            serverIpAddress: "10.0.0.1".ipStringToData!
        ).data

        bytes.append(contentsOf: HandshakeExtensionTypes.handshakeRequest.rawValue.bytes)
        bytes.append(contentsOf: UInt16(0xFFFF).bytes) // claims 256KB of payload

        XCTAssertNil(SrtHandshake(data: bytes))
    }

    // MARK: Handshake classification

    func testInductionResponseIsRecognised() throws {
        let response = SrtHandshake.makeInductionResponse(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0x0BADF00D,
            peerIpAddress: "10.0.0.1".ipStringToData!
        )

        let decoded = try XCTUnwrap(SrtHandshake(data: response.data))
        XCTAssertTrue(decoded.isInductionResponse)
    }

    /// libsrt sends extension field 1 (HSREQ) when there is no stream id,
    /// and 5 (HSREQ | CONFIG) when there is. Both are conclusion requests.
    func testConclusionRequestIsRecognisedWithAndWithoutStreamId() throws {
        for extensionField in [UInt16(1), UInt16(5)] {
            let handshake = SrtHandshake(
                hsVersion: .version5,
                encryptionField: 0,
                extensionField: extensionField,
                initialPacketSequenceNumber: 1,
                maximumTransmissionUnitSize: 1500,
                maximumFlowWindowSize: 8192,
                handshakeType: .conclusion,
                srtSocketID: 0xAABBCCDD,
                synCookie: 0x12345678,
                peerIPAddress: "10.0.0.1".ipStringToData!,
                extensionType: .none,
                extensionLength: 0,
                extensionContents: Data()
            )

            XCTAssertTrue(
                handshake.isConclusionRequest(synCookie: 0x12345678),
                "extension field \(extensionField) should be a conclusion request"
            )
        }
    }

    /// The caller receives a conclusion *response*, which carries HSRSP, not HSREQ.
    func testConclusionResponseIsRecognised() throws {
        let response = SrtHandshake.makeConclusionResponse(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 1,
            synCookie: 0x12345678,
            peerIpAddress: "10.0.0.1".ipStringToData!
        )

        XCTAssertTrue(response.isConclusionResponse)
        XCTAssertFalse(response.isConclusionRequest(synCookie: 0x12345678))
    }
}
