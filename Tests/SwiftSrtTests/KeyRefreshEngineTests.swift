import XCTest
@testable import SwiftSrt

/// Two socket engines wired back to back, so key material travels the way it
/// does on the wire: as user-defined control packets between data packets.
final class KeyRefreshEngineTests: XCTestCase {

    func testKeyMaterialRidesControlPacketsAndDataFollows() throws {
        let passphrase = "correct horse battery"
        let senderKeys = try SrtEncryption(passphrase: passphrase)
        let receiverKeys = try SrtEncryption.respond(toKeyMaterial: senderKeys.keyMaterial, passphrase: passphrase).get()

        let clock = SrtClock()
        let sender = SrtSocketContext(encrypted: true, socketId: 1, peerSocketId: 2, synCookie: 0)
        let receiver = SrtSocketContext(encrypted: true, socketId: 2, peerSocketId: 1, synCookie: 0)
        sender.encryption = senderKeys
        receiver.encryption = receiverKeys
        sender.ownInitialSequenceNumber = 100; sender.initialPacketSequenceNumber = 500
        receiver.ownInitialSequenceNumber = 500; receiver.initialPacketSequenceNumber = 100
        for engine in [sender, receiver] {
            engine.clock = clock
            /// No latency, so a tick releases whatever has arrived.
            engine.receiverTsbpdDelay = 0
            engine.senderTsbpdDelay = 0
            engine.activate()
        }
        sender.setKeyRefresh(rate: 20, preAnnounce: 5)

        let metrics = SrtMetricsService(logService: LogService(), interval: 60)
        let header = UdpHeader.blank

        /// Runs one event through an engine, returning what it sent and delivered.
        func pump(_ engine: SrtSocketContext, _ event: SrtSocketEvent) -> (sent: [SrtPacket], delivered: [SrtFrame]) {
            var sent: [SrtPacket] = [], delivered: [SrtFrame] = []
            engine.handle(event: event, header: header,
                          send: { packet, body in sent.append(SrtPacket(data: packet.data.prefix(16) + body).stamped(clock.now)) },
                          metrics: metrics) { delivered.append($0) }
            return (sent, delivered)
        }

        let userDefined: UInt32 = UInt32(ControlTypes.userDefined.rawValue) << 16
        var requests: [Data] = [], responses: [Data] = [], keyBits: [UInt8] = [], delivered: [Data] = []
        var expected: [Data] = []

        for index in 0..<60 {
            let plain = Data("payload \(index)".utf8)
            expected.append(plain)

            for packet in pump(sender, .send(plain)).sent {
                if packet.isData {
                    keyBits.append(try XCTUnwrap(DataPacketFrame(packet.data)).encryptionFlags)
                } else if packet.field1 & 0xFFFF_0000 == userDefined {
                    XCTAssertEqual(packet.field1 & 0xFFFF, 3, "KMREQ subtype")
                    requests.append(Data(packet.data.dropFirst(16)))
                }
                /// With no latency the packet is released as it arrives.
                let arrival = pump(receiver, .packet(packet))
                delivered += arrival.delivered.map(\.payload)
                for reply in arrival.sent {
                    if !reply.isData, reply.field1 & 0xFFFF_0000 == userDefined {
                        XCTAssertEqual(reply.field1 & 0xFFFF, 4, "KMRSP subtype")
                        responses.append(Data(reply.data.dropFirst(16)))
                    }
                    _ = pump(sender, .packet(reply))
                }
            }

            /// The receiver's tick releases the packet and acknowledges it.
            let tick = pump(receiver, .tick(clock.now))
            delivered += tick.delivered.map(\.payload)
            for reply in tick.sent { _ = pump(sender, .packet(reply)) }
            _ = pump(sender, .tick(clock.now))
        }

        /// The tail may still be waiting on its delivery time.
        var patience = 50
        while delivered.count < expected.count, patience > 0 {
            usleep(1000); patience -= 1
            delivered += pump(receiver, .tick(clock.now)).delivered.map(\.payload)
        }

        XCTAssertEqual(delivered, expected, "every payload opened, in order, across two key switches")
        XCTAssertEqual(requests.map { $0[3] & 0x03 }, [0b11, 0b10, 0b11, 0b01, 0b11], "both, odd alone, both, even alone, both")
        XCTAssertEqual(requests.map(\.count), [72, 56, 72, 56, 72])
        XCTAssertEqual(responses, requests, "each KMREQ echoed as KMRSP")
        XCTAssertEqual(Array(keyBits[0..<21]), Array(repeating: 1, count: 21), "even key first")
        XCTAssertEqual(Array(keyBits[21..<42]), Array(repeating: 2, count: 21), "odd key after the first switch")
        XCTAssertEqual(keyBits[42], 1, "even again after the second")

        XCTAssertEqual(sender.statistics.keyRefreshes, 2)
        XCTAssertEqual(sender.statistics.keyMaterialSent, 5, "each announcement answered before it could be retried")
        XCTAssertEqual(receiver.statistics.keyMaterialReceived, 5)
        XCTAssertEqual(receiver.statistics.keyMaterialRejected, 0)
        XCTAssertEqual(receiver.statistics.undecryptablePackets, 0)
        XCTAssertEqual(receiver.statistics.decryptedPackets, 60)
    }

    func testUnencryptedPeerRefusesKeyMaterial() throws {
        let clock = SrtClock()
        let receiver = SrtSocketContext(encrypted: false, socketId: 2, peerSocketId: 1, synCookie: 0)
        receiver.clock = clock
        receiver.activate()
        let metrics = SrtMetricsService(logService: LogService(), interval: 60)

        let request = try SrtEncryption(passphrase: "correct horse battery").keyMaterial
        let packet = SrtPacket(field1: ControlTypes.userDefined.asField | 3, socketID: 2, contents: request)

        var sent: [SrtPacket] = []
        receiver.handle(event: .packet(packet), header: .blank,
                        send: { header, body in sent.append(SrtPacket(data: header.data.prefix(16) + body)) },
                        metrics: metrics) { _ in }

        let reply = try XCTUnwrap(sent.first)
        XCTAssertEqual(reply.field1 & 0xFFFF, 4)
        XCTAssertEqual(Data(reply.data.dropFirst(16)), Data(SrtKeyMaterialState.noSecret.rawValue.bytes), "four-byte refusal")
        XCTAssertEqual(receiver.statistics.keyMaterialRejected, 1)
    }
}
