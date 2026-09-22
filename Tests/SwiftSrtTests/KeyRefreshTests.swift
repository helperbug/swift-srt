import XCTest
@testable import SwiftSrt

/// The sender's key rotation and the receiver following it, with libsrt's
/// schedule shrunk from millions of packets to a few dozen.
final class KeyRefreshTests: XCTestCase {

    private let passphrase = "correct horse battery"

    private func pair() throws -> (sender: SrtEncryption, receiver: SrtEncryption) {
        let sender = try SrtEncryption(passphrase: passphrase)
        let receiver = try SrtEncryption.respond(toKeyMaterial: sender.keyMaterial, passphrase: passphrase).get()
        return (sender, receiver)
    }

    /// Runs `count` packets sender to receiver, delivering and echoing any key
    /// material first, and returns the KK flags of every KM announced.
    private func run(_ count: Int, _ sender: SrtEncryption, _ receiver: SrtEncryption,
                     sequence: inout UInt32, sealed: inout [(UInt32, KeyMaterialFrame.KeyFlags, Data, Data)]) throws -> [KeyMaterialFrame.KeyFlags] {
        var announced: [KeyMaterialFrame.KeyFlags] = []
        for _ in 0..<count {
            sender.manageKeys()
            for material in sender.keyMaterialToSend(now: 0, rttMicroseconds: 0) {
                announced.append(try XCTUnwrap(KeyMaterialFrame(material)).keyFlags)
                let echo = try receiver.install(keyMaterial: material).get()
                XCTAssertTrue(sender.acknowledge(keyMaterialResponse: echo))
            }
            let plain = Data("packet \(sequence)".utf8)
            let flags = sender.activeKey
            let body = try XCTUnwrap(sender.encrypt(plain, sequence: sequence))
            XCTAssertEqual(receiver.decrypt(body, sequence: sequence, keyFlags: flags), plain, "sequence \(sequence)")
            sealed.append((sequence, flags, body, plain))
            sequence &+= 1
        }
        return announced
    }

    func testScheduleFollowsHaicrypt() throws {
        let (sender, receiver) = try pair()
        sender.setRefresh(rate: 20, preAnnounce: 5)
        var sequence: UInt32 = 1000
        var sealed: [(UInt32, KeyMaterialFrame.KeyFlags, Data, Data)] = []

        /// Both keys go out 5 packets before the switch at 20; the old key is
        /// dropped and the survivor re-announced 5 packets after; repeat.
        let announced = try run(60, sender, receiver, sequence: &sequence, sealed: &sealed)

        XCTAssertEqual(announced, [.both, .odd, .both, .even, .both])
        XCTAssertEqual(sender.refreshes, 2)
        XCTAssertEqual(sender.activeKey, .even, "back on the even key after two switches")
        XCTAssertEqual(receiver.installs, 5)

        let parities = sealed.map(\.1)
        XCTAssertEqual(parities.prefix(21).allSatisfy { $0 == .even }, true)
        XCTAssertEqual(parities[21], .odd, "the switch lands on packet 22")
        XCTAssertEqual(parities[42], .even)
    }

    func testTwoKeyMaterialLayout() throws {
        let (sender, _) = try pair()
        sender.setRefresh(rate: 20, preAnnounce: 5)
        for sequence in 0..<17 { sender.manageKeys(); _ = sender.encrypt(Data([0]), sequence: UInt32(sequence)) }

        let material = try XCTUnwrap(sender.keyMaterialToSend(now: 0, rttMicroseconds: 0).first)
        XCTAssertEqual(material.count, 16 + 16 + 2 * 16 + 8, "header, salt, two wrapped keys and the wrap tag")
        XCTAssertEqual(material[3] & 0x03, 0b11, "KK says both")
        XCTAssertEqual(material[15], 4, "key length still 16 bytes")
        let frame = try XCTUnwrap(KeyMaterialFrame(material))
        XCTAssertEqual(frame.salt, sender.salt)
        XCTAssertEqual(frame.wrappedKey.count, 40)
    }

    func testLatePacketsUnderTheOldKeyStillOpen() throws {
        let (sender, receiver) = try pair()
        sender.setRefresh(rate: 20, preAnnounce: 5)
        var sequence: UInt32 = 0
        var sealed: [(UInt32, KeyMaterialFrame.KeyFlags, Data, Data)] = []

        _ = try run(25, sender, receiver, sequence: &sequence, sealed: &sealed)
        XCTAssertEqual(sender.activeKey, .odd)

        /// A packet sealed under even before the switch arrives after it.
        let late = sealed[3]
        XCTAssertEqual(receiver.decrypt(late.2, sequence: late.0, keyFlags: late.1), late.3)
        XCTAssertNotEqual(receiver.decrypt(late.2, sequence: late.0, keyFlags: .odd), late.3, "wrong key, wrong bytes: CTR never refuses")
    }

    func testAnnouncementRetriesOnRttThenGivesUp() throws {
        let (sender, _) = try pair()
        sender.setRefresh(rate: 20, preAnnounce: 5)
        for sequence in 0..<17 { sender.manageKeys(); _ = sender.encrypt(Data([0]), sequence: UInt32(sequence)) }

        let rtt: UInt32 = 10_000
        XCTAssertEqual(sender.keyMaterialToSend(now: 0, rttMicroseconds: rtt).count, 1, "new material goes at once")
        XCTAssertEqual(sender.keyMaterialToSend(now: 5_000, rttMicroseconds: rtt).count, 0, "not before 1.5 RTT")
        XCTAssertEqual(sender.keyMaterialToSend(now: 15_000, rttMicroseconds: rtt).count, 1)

        var sends = 2
        var now: UInt32 = 15_000
        while true {
            now += 15_000
            let due = sender.keyMaterialToSend(now: now, rttMicroseconds: rtt)
            if due.isEmpty { break }
            sends += due.count
        }
        XCTAssertEqual(sends, SrtEncryption.announcementRetries)
    }

    func testEchoSettlesOnlyMatchingMaterial() throws {
        let (sender, _) = try pair()
        sender.setRefresh(rate: 20, preAnnounce: 5)
        for sequence in 0..<17 { sender.manageKeys(); _ = sender.encrypt(Data([0]), sequence: UInt32(sequence)) }
        let material = try XCTUnwrap(sender.keyMaterialToSend(now: 0, rttMicroseconds: 0).first)

        XCTAssertFalse(sender.acknowledge(keyMaterialResponse: material.dropLast()))
        XCTAssertTrue(sender.acknowledge(keyMaterialResponse: material))
        XCTAssertEqual(sender.keyMaterialToSend(now: 1_000_000, rttMicroseconds: 0).count, 0, "settled, nothing to resend")
    }

    func testReceiverRefusesWhatItCannotUse() throws {
        let (_, receiver) = try pair()

        let longer = try SrtEncryption(passphrase: passphrase, keyLength: 32)
        XCTAssertEqual(receiver.install(keyMaterial: longer.keyMaterial), .failure(.keyLength), "key length is fixed for the connection")

        let stranger = try SrtEncryption(passphrase: "a different passphrase")
        XCTAssertEqual(receiver.install(keyMaterial: stranger.keyMaterial), .failure(.badSecret))

        XCTAssertEqual(receiver.install(keyMaterial: Data([1, 2, 3])), .failure(.keyMaterialMalformed))
        XCTAssertEqual(receiver.installs, 0)
    }
}
