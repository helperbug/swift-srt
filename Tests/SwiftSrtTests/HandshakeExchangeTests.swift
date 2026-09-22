import XCTest
@testable import SwiftSrt

/// Drives a caller and a listener against each other by pumping each side's
/// returned actions into the other. No sockets, no timing -- just the
/// four-packet caller/listener exchange.
final class HandshakeExchangeTests: XCTestCase {

    private let listenerIp = "10.0.0.1"
    private let callerIp = "10.0.0.9"

    func testCallerAndListenerCompleteHandshake() throws {
        let listenerSocketID: UInt32 = 0x0A0B0C0D
        let synCookie: UInt32 = 0x1A2B3C4D

        let caller = SrtCallerContext(
            srtSocketID: 0x11223344,
            initialPacketSequenceNumber: 100,
            synCookie: 0,
            peerIpAddress: listenerIp.ipStringToData!,
            encrypted: false,
            streamId: "input/live/test"
        )

        var callerSent: [Exchanged] = []
        var listenerSent: [Exchanged] = []
        var callerSockets: [SrtSocketContext] = []
        var listenerSockets: [SrtSocketContext] = []

        // The listener is created lazily, on the caller's induction request,
        // exactly as ConnectionContext does it.
        var listener: SrtListenerContext?

        func pumpToListener(_ actions: [HandshakeAction]) {
            callerSent += actions.sent
            callerSockets += actions.sockets
            for exchanged in actions.sent {
                if let listener {
                    pumpToCaller(listener.handleHandshake(handshake: exchanged.handshake))
                } else {
                    XCTAssertTrue(exchanged.handshake.isInductionRequest, "first packet must be an induction request")
                    let created = SrtListenerContext(
                        srtSocketID: listenerSocketID,
                        peerSocketID: exchanged.handshake.srtSocketID,
                        initialPacketSequenceNumber: exchanged.handshake.initialPacketSequenceNumber,
                        synCookie: synCookie,
                        peerIpAddress: callerIp.ipStringToData!,
                        encrypted: false
                    )
                    listener = created
                    pumpToCaller(created.start())
                }
            }
        }

        func pumpToCaller(_ actions: [HandshakeAction]) {
            listenerSent += actions.sent
            listenerSockets += actions.sockets
            for exchanged in actions.sent {
                pumpToListener(caller.handleHandshake(handshake: exchanged.handshake))
            }
        }

        pumpToListener(caller.start())

        // Four packets: induction request/response, conclusion request/response.
        XCTAssertEqual(callerSent.count, 2, "caller should send induction then conclusion")
        XCTAssertEqual(listenerSent.count, 2, "listener should answer both")

        // -- Induction request -------------------------------------------------
        let inductionRequest = callerSent[0]
        XCTAssertTrue(inductionRequest.handshake.isInductionRequest)
        XCTAssertEqual(inductionRequest.destinationSocketID, 0, "an induction request is addressed to socket 0")

        // -- Induction response ------------------------------------------------
        let inductionResponse = listenerSent[0]
        XCTAssertTrue(inductionResponse.handshake.isInductionResponse)
        XCTAssertEqual(inductionResponse.handshake.srtSocketID, listenerSocketID, "the listener advertises its own socket ID")
        XCTAssertEqual(inductionResponse.handshake.synCookie, synCookie)
        XCTAssertEqual(inductionResponse.destinationSocketID, caller.srtSocketID, "the response is addressed to the caller's socket")

        // -- Conclusion request ------------------------------------------------
        let conclusionRequest = callerSent[1]
        XCTAssertTrue(conclusionRequest.handshake.isConclusionRequest(synCookie: synCookie), "the caller must echo the cookie it was given")
        XCTAssertEqual(conclusionRequest.handshake.srtSocketID, caller.srtSocketID)
        XCTAssertEqual(conclusionRequest.destinationSocketID, 0,
                       "libsrt's listener only accepts a conclusion request addressed to socket 0; its own caller sends 0")
        XCTAssertEqual(conclusionRequest.handshake.streamId, "input/live/test")
        XCTAssertEqual(conclusionRequest.handshake.srtVersion, SrtHandshake.srtLibraryVersion)

        // -- Conclusion response -----------------------------------------------
        let conclusionResponse = listenerSent[1]
        XCTAssertTrue(conclusionResponse.handshake.isConclusionResponse)
        XCTAssertEqual(conclusionResponse.destinationSocketID, caller.srtSocketID)
        XCTAssertEqual(conclusionResponse.handshake.srtVersion, SrtHandshake.srtLibraryVersion)

        // -- Both sides ended up connected -------------------------------------
        let listenerSocket = try XCTUnwrap(listenerSockets.first, "listener never created a socket")
        let callerSocket = try XCTUnwrap(callerSockets.first, "caller never created a socket")

        /// Each side keys its socket by its OWN ID, because that is what the peer
        /// puts in the destination field of every packet it sends.
        XCTAssertEqual(callerSocket.socketId, caller.srtSocketID)
        XCTAssertEqual(callerSocket.peerSocketId, listenerSocketID)
        XCTAssertEqual(listenerSocket.socketId, listenerSocketID)
        XCTAssertEqual(listenerSocket.peerSocketId, caller.srtSocketID)
    }

    /// A conclusion request carrying someone else's cookie must not connect.
    func testListenerRejectsWrongCookie() throws {
        let listener = SrtListenerContext(
            srtSocketID: 0x0A0B0C0D,
            peerSocketID: 0x11223344,
            initialPacketSequenceNumber: 0,
            synCookie: 0x1A2B3C4D,
            peerIpAddress: callerIp.ipStringToData!,
            encrypted: false
        )

        let induction = listener.start()
        XCTAssertEqual(induction.sent.count, 1, "the induction response")

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

        let outcome = listener.handleHandshake(handshake: forged)

        XCTAssertTrue(outcome.sockets.isEmpty, "a mismatched cookie must not establish a connection")
        XCTAssertTrue(outcome.sent.isEmpty, "nothing should be sent in reply")
    }
}
