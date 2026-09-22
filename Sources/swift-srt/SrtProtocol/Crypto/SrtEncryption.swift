//
//  SrtEncryption.swift
//  swift-srt
//
//  One stream's keys. The initiator makes a salt and a stream key, wraps the
//  key under a KEK derived from the passphrase, and sends that as KMREQ. The
//  responder derives the same KEK from the same passphrase and salt, unwraps,
//  and echoes the message back as KMRSP. If it cannot, it says why in four
//  bytes. Either way both ends then hold the same stream key.
//

import Foundation

/// The four-byte answer when a key exchange fails, as libsrt numbers them.
public enum SrtKeyMaterialState: UInt32, Sendable {
    case unsecured = 0
    case securing = 1
    case secured = 2
    case noSecret = 3
    case badSecret = 4
    case badCryptoMode = 5
}

public enum SrtEncryptionError: Error, Equatable {
    case passphraseLength
    case keyLength
    case keyMaterialMalformed
    case noSecret
    case badSecret
    case badCryptoMode
    case peerRejected(SrtKeyMaterialState)
}

public final class SrtEncryption {

    public let keyLength: Int
    public let salt: Data
    private let streamKey: Data
    private let keyEncryptingKey: Data

    /// The KM message as first built or accepted; KMRSP echoes it verbatim.
    public let keyMaterial: Data

    /// Handshake encryption field value for this key size.
    public var encryptionField: UInt16 {
        switch keyLength {
        case 16: return 2
        case 24: return 3
        default: return 4
        }
    }

    public static func keyLength(forEncryptionField field: UInt16) -> Int? {
        switch field {
        case 2: return 16
        case 3: return 24
        case 4: return 32
        default: return nil
        }
    }

    /// Initiator: fresh salt and key for a new stream.
    public convenience init(passphrase: String, keyLength: Int = 16) throws {
        guard (SrtCrypto.passphraseMinimum...SrtCrypto.passphraseMaximum).contains(passphrase.utf8.count) else {
            throw SrtEncryptionError.passphraseLength
        }
        guard [16, 24, 32].contains(keyLength) else { throw SrtEncryptionError.keyLength }

        let salt = SrtCrypto.randomBytes(SrtCrypto.saltLength)
        let streamKey = SrtCrypto.randomBytes(keyLength)

        guard let kek = SrtCrypto.keyEncryptingKey(passphrase: passphrase, salt: salt, keyLength: keyLength),
              let wrapped = SrtCrypto.wrapKey(streamKey, with: kek) else {
            throw SrtEncryptionError.keyLength
        }

        let frame = KeyMaterialFrame(keyFlags: .even, keyLength: keyLength, salt: salt, wrappedKey: wrapped)
        self.init(keyLength: keyLength, salt: salt, streamKey: streamKey, keyEncryptingKey: kek, keyMaterial: frame.data)
    }

    private init(keyLength: Int, salt: Data, streamKey: Data, keyEncryptingKey: Data, keyMaterial: Data) {
        self.keyLength = keyLength
        self.salt = salt
        self.streamKey = streamKey
        self.keyEncryptingKey = keyEncryptingKey
        self.keyMaterial = keyMaterial
    }

    /// Responder: take the peer's KMREQ and our passphrase, and either come
    /// back with the same keys or with the reason we could not.
    public static func respond(toKeyMaterial request: Data, passphrase: String?) -> Result<SrtEncryption, SrtEncryptionError> {

        guard let frame = KeyMaterialFrame(request) else {
            return .failure(.keyMaterialMalformed)
        }
        guard frame.cipher == KeyMaterialFrame.cipherAesCtr, frame.auth == 0 else {
            return .failure(.badCryptoMode)
        }
        guard let passphrase else {
            return .failure(.noSecret)
        }
        guard let kek = SrtCrypto.keyEncryptingKey(passphrase: passphrase, salt: frame.salt, keyLength: frame.keyLength),
              let keys = SrtCrypto.unwrapKey(frame.wrappedKey, with: kek),
              keys.count == frame.keyLength * frame.keyFlags.keyCount else {
            return .failure(.badSecret)
        }

        /// With both keys present the even one comes first; we use the even key.
        let streamKey = Data(keys.prefix(frame.keyLength))
        return .success(SrtEncryption(keyLength: frame.keyLength, salt: frame.salt, streamKey: streamKey,
                                      keyEncryptingKey: kek, keyMaterial: request))
    }

    /// Initiator: interpret the KMRSP. Four bytes is a refusal.
    public func accept(keyMaterialResponse response: Data) -> Result<Void, SrtEncryptionError> {
        if response.count == 4 {
            var offset = 0
            let raw = response.toUInt32(from: &offset)
            let state = SrtKeyMaterialState(rawValue: raw) ?? SrtKeyMaterialState(rawValue: raw.byteSwapped) ?? .badSecret
            return .failure(.peerRejected(state))
        }
        guard response == keyMaterial else {
            return .failure(.badSecret)
        }
        return .success(())
    }

    /// The failure word to send when we are the one refusing.
    public static func refusal(_ error: SrtEncryptionError) -> Data {
        let state: SrtKeyMaterialState
        switch error {
        case .noSecret: state = .noSecret
        case .badCryptoMode: state = .badCryptoMode
        default: state = .badSecret
        }
        return Data(state.rawValue.bytes)
    }

    // MARK: Payload

    public func encrypt(_ payload: Data, sequence: UInt32) -> Data? {
        SrtCrypto.aesCtr(key: streamKey, iv: SrtCrypto.counterBlock(salt: salt, sequence: sequence), data: payload)
    }

    public func decrypt(_ payload: Data, sequence: UInt32) -> Data? {
        encrypt(payload, sequence: sequence)
    }
}
