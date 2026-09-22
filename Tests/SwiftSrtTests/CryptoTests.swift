import XCTest
@testable import SwiftSrt

private func hex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

final class CryptoPrimitiveTests: XCTestCase {

    /// RFC 6070 PBKDF2-HMAC-SHA1 vectors.
    func testPbkdf2Sha1KnownAnswers() {
        XCTAssertEqual(SrtCrypto.pbkdf2Sha1(passphrase: Data("password".utf8), salt: Data("salt".utf8), iterations: 1, keyLength: 20),
                       hex("0c60c80f961f0e71f3a9b524af6012062fe037a6"))
        XCTAssertEqual(SrtCrypto.pbkdf2Sha1(passphrase: Data("password".utf8), salt: Data("salt".utf8), iterations: 4096, keyLength: 20),
                       hex("4b007901b765489abead49d926f721d065a429c1"))
    }

    /// RFC 3394 section 4.1: 128-bit key wrapped under a 128-bit KEK.
    func testKeyWrapKnownAnswer() throws {
        let kek = hex("000102030405060708090A0B0C0D0E0F")
        let key = hex("00112233445566778899AABBCCDDEEFF")
        let wrapped = try XCTUnwrap(SrtCrypto.wrapKey(key, with: kek))
        XCTAssertEqual(wrapped, hex("1FA68B0A8112B447AEF34BD8FB5A7B829D3E862371D2CFE5"))
        XCTAssertEqual(SrtCrypto.unwrapKey(wrapped, with: kek), key)
    }

    func testUnwrapWithWrongKekFails() throws {
        let kek = hex("000102030405060708090A0B0C0D0E0F")
        let wrong = hex("0F0E0D0C0B0A09080706050403020100")
        let wrapped = try XCTUnwrap(SrtCrypto.wrapKey(hex("00112233445566778899AABBCCDDEEFF"), with: kek))
        XCTAssertNil(SrtCrypto.unwrapKey(wrapped, with: wrong), "the check value must catch a bad passphrase")
    }

    /// NIST SP 800-38A F.5.1, AES-128 CTR, first block.
    func testAesCtrKnownAnswer() {
        let key = hex("2b7e151628aed2a6abf7158809cf4f3c")
        let iv = hex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
        let plain = hex("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51")
        let cipher = hex("874d6191b620e3261bef6864990db6ce9806f66b7970fdff8617187bb9fffdff")
        XCTAssertEqual(SrtCrypto.aesCtr(key: key, iv: iv, data: plain), cipher)
        XCTAssertEqual(SrtCrypto.aesCtr(key: key, iv: iv, data: cipher), plain, "CTR is its own inverse")
    }

    /// hcrypt_SetCtrIV: zeros, index at bytes 10-13 little-endian, XOR salt over 0-13.
    func testCounterBlockLayout() {
        let salt = hex("000102030405060708090A0B0C0D0E0F")
        let iv = SrtCrypto.counterBlock(salt: salt, sequence: 0x01020304)
        XCTAssertEqual(iv.count, 16)
        XCTAssertEqual(Data(iv.prefix(10)), Data(salt.prefix(10)), "bytes before the index are salt XOR zero")
        XCTAssertEqual(iv[10], 0x01 ^ 0x0A, "network byte order, high byte first")
        XCTAssertEqual(iv[11], 0x02 ^ 0x0B)
        XCTAssertEqual(iv[12], 0x03 ^ 0x0C)
        XCTAssertEqual(iv[13], 0x04 ^ 0x0D)
        XCTAssertEqual(iv[14], 0, "block counter starts at zero, not salted")
        XCTAssertEqual(iv[15], 0)
    }
}

final class KeyMaterialTests: XCTestCase {

    func testFrameLayoutMatchesHaicrypt() throws {
        let salt = SrtCrypto.randomBytes(16)
        let wrapped = Data(repeating: 0xAB, count: 24)
        let frame = KeyMaterialFrame(keyFlags: .even, keyLength: 16, salt: salt, wrappedKey: wrapped)

        XCTAssertEqual(frame.data.count, 16 + 16 + 24)
        XCTAssertEqual(frame.data[0], 0x12, "version 1, packet type 2")
        XCTAssertEqual(frame.data[1], 0x20); XCTAssertEqual(frame.data[2], 0x29)
        XCTAssertEqual(frame.data[3], 0x01, "even key")
        XCTAssertEqual(frame.data[8], 2, "AES-CTR"); XCTAssertEqual(frame.data[9], 0, "no auth"); XCTAssertEqual(frame.data[10], 2, "TS/SRT")
        XCTAssertEqual(frame.data[14], 4, "salt 16/4"); XCTAssertEqual(frame.data[15], 4, "key 16/4")

        let parsed = try XCTUnwrap(KeyMaterialFrame(frame.data))
        XCTAssertEqual(parsed.salt, salt)
        XCTAssertEqual(parsed.wrappedKey, wrapped)
        XCTAssertEqual(parsed.keyLength, 16)
    }

    func testFrameRejectsInconsistentLength() {
        let frame = KeyMaterialFrame(keyFlags: .even, keyLength: 16, salt: Data(count: 16), wrappedKey: Data(count: 24))
        XCTAssertNil(KeyMaterialFrame(frame.data.dropLast()), "one byte short")
        XCTAssertNil(KeyMaterialFrame(frame.data + Data([0])), "one byte long")
        var bad = frame.data; bad[1] = 0
        XCTAssertNil(KeyMaterialFrame(bad), "wrong signature")
        var badKey = frame.data; badKey[15] = 5
        XCTAssertNil(KeyMaterialFrame(badKey), "20 byte keys do not exist")
    }

    func testExchangeSucceedsWithSharedPassphrase() throws {
        let initiator = try SrtEncryption(passphrase: "correct horse battery")
        let responder = try SrtEncryption.respond(toKeyMaterial: initiator.keyMaterial, passphrase: "correct horse battery").get()

        XCTAssertEqual(responder.keyMaterial, initiator.keyMaterial, "the response echoes the request")
        XCTAssertNil(initiator.accept(keyMaterialResponse: responder.keyMaterial).failure, "echo is accepted")

        let plain = Data((0..<1316).map { UInt8($0 & 0xFF) })
        let sealed = try XCTUnwrap(initiator.encrypt(plain, sequence: 12345))
        XCTAssertNotEqual(sealed, plain)
        XCTAssertEqual(responder.decrypt(sealed, sequence: 12345), plain, "same keys on both ends")
        XCTAssertNotEqual(responder.decrypt(sealed, sequence: 12346), plain, "the sequence number is part of the keystream")
    }

    func testExchangeRefusals() throws {
        let initiator = try SrtEncryption(passphrase: "correct horse battery")

        XCTAssertEqual(SrtEncryption.respond(toKeyMaterial: initiator.keyMaterial, passphrase: nil).failure, .noSecret)
        XCTAssertEqual(SrtEncryption.respond(toKeyMaterial: initiator.keyMaterial, passphrase: "wrong wrong wrong").failure, .badSecret)
        XCTAssertEqual(SrtEncryption.respond(toKeyMaterial: Data([1, 2, 3]), passphrase: "correct horse battery").failure, .keyMaterialMalformed)

        XCTAssertEqual(initiator.accept(keyMaterialResponse: SrtEncryption.refusal(.badSecret)).failure, .peerRejected(.badSecret))
        XCTAssertEqual(initiator.accept(keyMaterialResponse: SrtEncryption.refusal(.noSecret)).failure, .peerRejected(.noSecret))
    }

    func testPassphraseLengthIsEnforced() {
        XCTAssertThrowsError(try SrtEncryption(passphrase: "short"))
        XCTAssertThrowsError(try SrtEncryption(passphrase: String(repeating: "x", count: 80)))
        XCTAssertNoThrow(try SrtEncryption(passphrase: String(repeating: "x", count: 79)))
    }

    /// Key material rides in the conclusion as-is; a word-reversed copy is
    /// still recognised by its signature.
    func testHandshakeCarriesKeyMaterial() throws {
        let encryption = try SrtEncryption(passphrase: "correct horse battery")
        let request = SrtHandshake.makeConclusionRequest(
            srtSocketID: 1, initialPacketSequenceNumber: 0, synCookie: 1, peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.handshakeRequest: HandshakeExtensionMessage(srtVersion: 1, srtFlags: 0, receiverTsbpdDelay: 1, senderTsbpdDelay: 1).data,
                         .keyMaterialRequest: encryption.keyMaterial],
            encryptionField: encryption.encryptionField)
        let parsed = try XCTUnwrap(SrtHandshake(data: request.data))
        XCTAssertEqual(parsed.keyMaterialRequest, encryption.keyMaterial)
        XCTAssertEqual(parsed.extensionField, 3, "HSREQ | KMREQ")
        XCTAssertEqual(parsed.encryptionField, 2, "AES-128")

        let reversed = SrtHandshake.makeConclusionRequest(
            srtSocketID: 1, initialPacketSequenceNumber: 0, synCookie: 1, peerIpAddress: "10.0.0.1".ipStringToData!,
            extensions: [.keyMaterialRequest: SrtHandshake.wordReversed(encryption.keyMaterial)])
        XCTAssertEqual(try XCTUnwrap(SrtHandshake(data: reversed.data)).keyMaterialRequest, encryption.keyMaterial, "tolerated either way")
    }
}

private extension Result where Failure == SrtEncryptionError {
    var failure: SrtEncryptionError? { if case .failure(let e) = self { return e }; return nil }
}

final class KeyMaterialHandshakeTests: XCTestCase {

    /// A conclusion response built with key material must carry it on the wire.
    func testConclusionResponseCarriesKeyMaterialResponse() throws {
        let encryption = try SrtEncryption(passphrase: "correct horse battery")
        let response = SrtHandshake.makeConclusionResponse(
            srtSocketID: 7, initialPacketSequenceNumber: 0, synCookie: 0, peerIpAddress: "10.0.0.1".ipStringToData!,
            keyMaterialResponse: encryption.keyMaterial, encryptionField: 2)

        XCTAssertEqual(response.extensions.count, 2, "HSRSP and KMRSP")
        XCTAssertEqual(response.extensionField, 3)

        let bytes = response.data
        XCTAssertEqual(bytes.count, 48 + 4 + 12 + 4 + encryption.keyMaterial.count, "both TLVs serialised")

        let parsed = try XCTUnwrap(SrtHandshake(data: bytes))
        XCTAssertEqual(parsed.keyMaterialResponse, encryption.keyMaterial)
        XCTAssertTrue(parsed.isConclusionResponse)
    }

    /// The responder echoes exactly what it parsed, even when that came in as
    /// a slice of a larger buffer.
    func testResponderEchoesSlicedRequest() throws {
        let initiator = try SrtEncryption(passphrase: "correct horse battery")
        var buffer = Data([0xAA, 0xBB, 0xCC])
        buffer.append(initiator.keyMaterial)
        let slice = buffer[3...]
        let responder = try SrtEncryption.respond(toKeyMaterial: slice, passphrase: "correct horse battery").get()
        XCTAssertEqual(responder.keyMaterial, initiator.keyMaterial)
        XCTAssertEqual(responder.keyMaterial.count, initiator.keyMaterial.count)
    }
}
