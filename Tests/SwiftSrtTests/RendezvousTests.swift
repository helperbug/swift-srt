import XCTest
@testable import SwiftSrt

/// Two rendezvous machines pumped against each other.
final class RendezvousTests: XCTestCase {

    private func pump(_ a: SrtRendezvousContext, _ b: SrtRendezvousContext, passes: Int = 6) -> (aSockets: [SrtSocketContext], bSockets: [SrtSocketContext], aSent: Int, bSent: Int) {
        var toB = a.start().sent.map(\.handshake)
        var toA = b.start().sent.map(\.handshake)
        var aSockets: [SrtSocketContext] = [], bSockets: [SrtSocketContext] = []
        var aSent = 1, bSent = 1

        for _ in 0..<passes {
            var nextToA: [SrtHandshake] = [], nextToB: [SrtHandshake] = []
            for handshake in toB {
                let actions = b.handleHandshake(handshake: handshake)
                bSockets += actions.sockets
                nextToA += actions.sent.map(\.handshake); bSent += actions.sent.count
            }
            for handshake in toA {
                let actions = a.handleHandshake(handshake: handshake)
                aSockets += actions.sockets
                nextToB += actions.sent.map(\.handshake); aSent += actions.sent.count
            }
            toA = nextToA; toB = nextToB
            if toA.isEmpty && toB.isEmpty { break }
        }
        return (aSockets, bSockets, aSent, bSent)
    }

    func testBothSidesConnectAndRolesFollowCookies() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 100, peerIpAddress: "10.0.0.2".ipStringToData!)
        let b = SrtRendezvousContext(srtSocketID: 2, initialPacketSequenceNumber: 200, peerIpAddress: "10.0.0.1".ipStringToData!)

        let result = pump(a, b)

        XCTAssertEqual(a.state, .active); XCTAssertEqual(b.state, .active)
        XCTAssertEqual(result.aSockets.count, 1); XCTAssertEqual(result.bSockets.count, 1)

        let expectedInitiator: SrtRendezvousContext = Int32(bitPattern: a.cookie &- b.cookie) > 0 ? a : b
        XCTAssertEqual(expectedInitiator.role, .initiator)
        XCTAssertNotEqual(a.role, b.role)

        let aSocket = try XCTUnwrap(result.aSockets.first), bSocket = try XCTUnwrap(result.bSockets.first)
        XCTAssertEqual(aSocket.socketId, 1); XCTAssertEqual(aSocket.peerSocketId, 2)
        XCTAssertEqual(bSocket.socketId, 2); XCTAssertEqual(bSocket.peerSocketId, 1)
        XCTAssertEqual(aSocket.initialPacketSequenceNumber, 200, "a's receive buffer starts at b's ISN")
        XCTAssertEqual(bSocket.initialPacketSequenceNumber, 100)
    }

    func testEncryptedRendezvousSharesKeys() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!, passphrase: "correct horse battery")
        let b = SrtRendezvousContext(srtSocketID: 2, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.1".ipStringToData!, passphrase: "correct horse battery")
        let result = pump(a, b)
        XCTAssertEqual(a.state, .active); XCTAssertEqual(b.state, .active)
        let plain = Data([1, 2, 3, 4, 5])
        let sealed = try XCTUnwrap(result.aSockets.first?.encryption?.encrypt(plain, sequence: 9))
        XCTAssertEqual(try XCTUnwrap(result.bSockets.first).encryption?.decrypt(sealed, sequence: 9), plain)
    }

    func testMismatchedPassphraseDoesNotConnect() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!, passphrase: "correct horse battery")
        let b = SrtRendezvousContext(srtSocketID: 2, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.1".ipStringToData!, passphrase: "something else entirely")
        let result = pump(a, b)
        XCTAssertTrue(result.aSockets.isEmpty && result.bSockets.isEmpty, "neither side may come up")
        XCTAssertTrue(a.state == .shutdown || b.state == .shutdown)
    }

    /// libsrt keeps its cookie on every rendezvous packet, so a conclusion that
    /// arrives before its wave still settles the roles.
    func testConclusionBeforeWaveLetsCookieDecide() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!)
        _ = a.start()

        /// The peer holds the smaller cookie and sent libsrt's bare "attention"
        /// conclusion: it is waiting for us to lead.
        let attention = SrtHandshake.makeConclusionRequest(
            srtSocketID: 2, initialPacketSequenceNumber: 0, synCookie: a.cookie &- 1,
            peerIpAddress: "10.0.0.1".ipStringToData!, extensions: [:])
        let sent = a.handleHandshake(handshake: attention).sent
        XCTAssertEqual(a.role, .initiator); XCTAssertEqual(a.state, .initiating)
        XCTAssertEqual(sent.count, 1)
        XCTAssertNotNil(sent[0].handshake.extensions[.handshakeRequest], "we lead with HSREQ")
    }

    func testConclusionWithLargerCookieMakesUsResponder() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!)
        _ = a.start()

        let request = SrtHandshake.makeConclusionRequest(
            srtSocketID: 2, initialPacketSequenceNumber: 0, synCookie: a.cookie &+ 1,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.handshakeRequest: HandshakeExtensionMessage(
                srtVersion: SrtHandshake.srtLibraryVersion, srtFlags: SrtHandshake.defaultSrtFlags,
                receiverTsbpdDelay: 120, senderTsbpdDelay: 120).data])
        let sent = a.handleHandshake(handshake: request).sent
        XCTAssertEqual(a.role, .responder); XCTAssertEqual(a.state, .responding)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].handshake.isConclusionResponse, "we answer with HSRSP")
    }

    /// A peer following the draft sends conclusions with no cookie; that peer
    /// only concludes once it has decided it leads.
    func testConclusionWithNoCookieMeansPeerLeads() throws {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!)
        _ = a.start()

        let request = SrtHandshake.makeConclusionRequest(
            srtSocketID: 2, initialPacketSequenceNumber: 0, synCookie: 0,
            peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.handshakeRequest: HandshakeExtensionMessage(
                srtVersion: SrtHandshake.srtLibraryVersion, srtFlags: SrtHandshake.defaultSrtFlags,
                receiverTsbpdDelay: 120, senderTsbpdDelay: 120).data])
        let sent = a.handleHandshake(handshake: request).sent
        XCTAssertEqual(a.role, .responder)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent[0].handshake.isConclusionResponse)
    }

    func testRetryResendsLastPacket() {
        let a = SrtRendezvousContext(srtSocketID: 1, initialPacketSequenceNumber: 0, peerIpAddress: "10.0.0.2".ipStringToData!)
        let first = a.start().sent
        let again = a.retry().sent
        XCTAssertEqual(first.count, 1); XCTAssertEqual(again.count, 1)
        XCTAssertEqual(again[0].handshake.synCookie, first[0].handshake.synCookie, "same wave, same cookie")
    }
}
