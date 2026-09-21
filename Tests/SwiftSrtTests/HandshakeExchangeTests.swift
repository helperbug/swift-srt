import XCTest
@testable import SwiftSrt

/// Drives a caller and a listener against each other, wiring each side's `send`
/// closure straight into the other's `handleHandshake`. No sockets, no timing --
/// just the four-packet caller/listener exchange.
final class HandshakeExchangeTests: XCTestCase {

    /// One packet as it would go on the wire, decoded back into a handshake.
    private struct Exchanged {
        let destinationSocketID: UInt32
        let handshake: SrtHandshake
    }

    private let listenerIp = "10.0.0.1"
    private let callerIp = "10.0.0.9"

    func testCallerAndListenerCompleteHandshake() throws {
        var callerToListener: [Exchanged] = []
        var listenerToCaller: [Exchanged] = []

        var listener: SrtListenerContext?
        var caller: SrtCallerContext?

        var callerSocket: SrtSocketProtocol?
        var listenerSocket: SrtSocketProtocol?

        let listenerSocketID: UInt32 = 0x0A0B0C0D
        let synCookie: UInt32 = 0x1A2B3C4D

        // The listener is created lazily, on the caller's induction request, exactly
        // as ConnectionContext does it.
        let callerSend: (SrtPacket, Data) -> Void = { packet, contents in
            let handshake = SrtHandshake(data: contents)
            XCTAssertNotNil(handshake, "caller emitted an unparseable handshake")
            guard let handshake else { return }

            callerToListener.append(
                Exchanged(destinationSocketID: packet.destinationSocketID, handshake: handshake)
            )

            if let listener {
                listener.handleHandshake(handshake: handshake)
            } else {
                XCTAssertTrue(handshake.isInductionRequest, "first packet must be an induction request")

                listener = SrtListenerContext(
                    srtSocketID: listenerSocketID,
                    peerSocketID: handshake.srtSocketID,
                    initialPacketSequenceNumber: handshake.initialPacketSequenceNumber,
                    synCookie: synCookie,
                    peerIpAddress: self.callerIp.ipStringToData!,
                    encrypted: false,
                    send: { packet, contents in
                        let response = SrtHandshake(data: contents)
                        XCTAssertNotNil(response, "listener emitted an unparseable handshake")
                        guard let response else { return }

                        listenerToCaller.append(
                            Exchanged(destinationSocketID: packet.destinationSocketID, handshake: response)
                        )

                        caller?.handleHandshake(handshake: response)
                    },
                    onSocketCreated: { listenerSocket = $0 }
                )
                listener?.start()
            }
        }

        // Creating the caller kicks off the exchange from its start state.
        caller = SrtCallerContext(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 100,
            synCookie: 0,
            peerIpAddress: listenerIp.ipStringToData!,
            encrypted: false,
            streamId: "input/live/test",
            send: callerSend,
            onSocketCreated: { callerSocket = $0 }
        )

        let caller1 = try XCTUnwrap(caller)
        caller1.start()

        // Four packets: induction request/response, conclusion request/response.
        XCTAssertEqual(callerToListener.count, 2, "caller should send induction then conclusion")
        XCTAssertEqual(listenerToCaller.count, 2, "listener should answer both")

        // -- Induction request -------------------------------------------------
        let inductionRequest = callerToListener[0]
        XCTAssertTrue(inductionRequest.handshake.isInductionRequest)
        XCTAssertEqual(inductionRequest.destinationSocketID, 0,
                       "an induction request is addressed to socket 0")

        // -- Induction response ------------------------------------------------
        let inductionResponse = listenerToCaller[0]
        XCTAssertTrue(inductionResponse.handshake.isInductionResponse)
        XCTAssertEqual(inductionResponse.handshake.srtSocketID, listenerSocketID,
                       "the listener advertises its own socket ID")
        XCTAssertEqual(inductionResponse.handshake.synCookie, synCookie)
        XCTAssertEqual(inductionResponse.destinationSocketID, caller1.srtSocketID,
                       "the response is addressed to the caller's socket")

        // -- Conclusion request ------------------------------------------------
        let conclusionRequest = callerToListener[1]
        XCTAssertTrue(conclusionRequest.handshake.isConclusionRequest(synCookie: synCookie),
                      "the caller must echo the cookie it was given")
        XCTAssertEqual(conclusionRequest.handshake.srtSocketID, caller1.srtSocketID)
        XCTAssertEqual(conclusionRequest.destinationSocketID, listenerSocketID,
                       "past induction the caller addresses the listener's socket")
        XCTAssertEqual(conclusionRequest.handshake.streamId, "input/live/test")
        XCTAssertEqual(conclusionRequest.handshake.srtVersion, SrtHandshake.srtLibraryVersion)

        // -- Conclusion response -----------------------------------------------
        let conclusionResponse = listenerToCaller[1]
        XCTAssertTrue(conclusionResponse.handshake.isConclusionResponse)
        XCTAssertEqual(conclusionResponse.destinationSocketID, caller1.srtSocketID)
        XCTAssertEqual(conclusionResponse.handshake.srtVersion, SrtHandshake.srtLibraryVersion)

        // -- Both sides ended up connected -------------------------------------
        XCTAssertNotNil(listenerSocket, "listener never created a socket")
        XCTAssertNotNil(callerSocket, "caller never created a socket")
        /// Each side keys its socket by its OWN ID, because that is what the peer
        /// puts in the destination field of every packet it sends. Keying by the
        /// peer's ID instead makes every inbound packet fail to match.
        XCTAssertEqual(callerSocket?.socketId, caller1.srtSocketID)
        XCTAssertEqual(callerSocket?.peerSocketId, listenerSocketID)

        XCTAssertEqual(listenerSocket?.socketId, listenerSocketID)
        XCTAssertEqual(listenerSocket?.peerSocketId, caller1.srtSocketID)
    }

    /// A conclusion request carrying someone else's cookie must not connect.
    func testListenerRejectsWrongCookie() throws {
        var listenerSocket: SrtSocketProtocol?
        var sent: [SrtHandshake] = []

        let listener = SrtListenerContext(
            srtSocketID: 0x0A0B0C0D,
            peerSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0x1A2B3C4D,
            peerIpAddress: callerIp.ipStringToData!,
            encrypted: false,
            send: { _, contents in
                if let handshake = SrtHandshake(data: contents) { sent.append(handshake) }
            },
            onSocketCreated: { listenerSocket = $0 }
        )

        listener.start()

        let forged = SrtHandshake.makeConclusionRequest(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0xDEADBEEF, // not the cookie we issued
            peerIpAddress: callerIp.ipStringToData!,
            extensions: [.handshakeRequest: HandshakeExtensionMessage(
                srtVersion: SrtHandshake.srtLibraryVersion,
                srtFlags: SrtHandshake.defaultSrtFlags,
                receiverTsbpdDelay: 120,
                senderTsbpdDelay: 120
            ).data]
        )

        listener.handleHandshake(handshake: forged)

        XCTAssertNil(listenerSocket, "a mismatched cookie must not establish a connection")
        XCTAssertEqual(sent.count, 1, "only the induction response should have been sent")
    }
}
