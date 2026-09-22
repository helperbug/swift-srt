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
//  Keys do not last forever. There are two slots, even and odd, and the
//  sender rotates between them on a packet count the way haicrypt does:
//  shortly before the active key expires it makes the other, announces both
//  in one KM, switches, and once late packets can no longer need the old
//  one, drops it and announces the survivor alone. The receiver just follows
//  the KK bits on each packet.
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

    public typealias KeyFlags = KeyMaterialFrame.KeyFlags

    /// libsrt's defaults: a key serves 2^24 packets; the next is announced
    /// 2^16 packets before the switch and the old one kept 2^16 after it.
    public static let defaultRefreshRate: UInt32 = 0x1000000
    public static let defaultPreAnnounce: UInt32 = 0x10000

    /// How many times a KM goes out unanswered before we stop asking.
    static let announcementRetries = 10

    public let keyLength: Int
    public private(set) var salt: Data
    private let passphrase: String
    private var keyEncryptingKey: Data

    /// Even in slot 0, odd in slot 1; nil is an empty slot.
    private var keys: [Data?]

    /// The key our own packets are sealed with, and the KK bits they carry.
    public private(set) var activeKey: KeyFlags

    /// Retired at the last switch and kept a while for late packets.
    private var deprecatedKey: KeyFlags?

    /// Packets sealed with the active key since it went active.
    private var packetsUnderActiveKey: UInt32 = 0
    private var nextKeyAnnounced = false

    public private(set) var refreshRate = SrtEncryption.defaultRefreshRate
    public private(set) var preAnnounce = SrtEncryption.defaultPreAnnounce

    /// The KM message that established the session; KMRSP echoes it verbatim.
    public let keyMaterial: Data

    /// Key material the peer has yet to echo, filed as libsrt files it: an
    /// even-only KM in slot 0, odd-only or both-keys in slot 1.
    private struct Announcement {
        var material: Data
        var retries: Int
        var lastSent: UInt32?
    }
    private var announcements: [Announcement?] = [nil, nil]

    /// Switches made as sender; key material taken in as receiver.
    public private(set) var refreshes = 0
    public private(set) var installs = 0

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
        self.init(passphrase: passphrase, keyLength: keyLength, salt: salt, keyEncryptingKey: kek,
                  keys: [streamKey, nil], activeKey: .even, keyMaterial: frame.data)
    }

    private init(passphrase: String, keyLength: Int, salt: Data, keyEncryptingKey: Data,
                 keys: [Data?], activeKey: KeyFlags, keyMaterial: Data) {
        self.passphrase = passphrase
        self.keyLength = keyLength
        self.salt = salt
        self.keyEncryptingKey = keyEncryptingKey
        self.keys = keys
        self.activeKey = activeKey
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

        var slots: [Data?] = [nil, nil]
        place(keys, from: frame, into: &slots)
        return .success(SrtEncryption(passphrase: passphrase, keyLength: frame.keyLength, salt: frame.salt,
                                      keyEncryptingKey: kek, keys: slots,
                                      activeKey: frame.keyFlags == .odd ? .odd : .even, keyMaterial: request))
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

    // MARK: Refresh

    /// Shorter periods than libsrt's defaults, for tests and for peers that
    /// ask. The pre-announce is held to half the refresh, as libsrt clamps it.
    public func setRefresh(rate: UInt32, preAnnounce: UInt32) {
        refreshRate = max(rate, 2)
        self.preAnnounce = max(1, min(preAnnounce, refreshRate / 2))
    }

    /// Sender: call before sealing each packet. This is haicrypt's
    /// `hcryptCtx_Tx_ManageKM`, on the count of packets under the active key.
    public func manageKeys() {
        let alternate: KeyFlags = activeKey == .even ? .odd : .even

        if packetsUnderActiveKey > refreshRate {
            /// End of this key's period: the other slot takes over.
            guard keys[Self.slot(alternate)] != nil else { return }
            deprecatedKey = activeKey
            activeKey = alternate
            packetsUnderActiveKey = 0
            nextKeyAnnounced = false
            refreshes += 1

        } else if packetsUnderActiveKey > refreshRate &- preAnnounce, !nextKeyAnnounced {
            /// The period is ending: make the next key and announce both.
            keys[Self.slot(alternate)] = SrtCrypto.randomBytes(keyLength)
            nextKeyAnnounced = true
            announce(keyFlags: .both)

        } else if let deprecatedKey, packetsUnderActiveKey > preAnnounce {
            /// Nothing late can still need the old key. Drop it, and tell the
            /// peer the active key stands alone now.
            keys[Self.slot(deprecatedKey)] = nil
            self.deprecatedKey = nil
            announce(keyFlags: activeKey)
        }
    }

    /// Wraps the named key or keys under the KEK and files the KM to send.
    /// With both, the even key goes first.
    private func announce(keyFlags: KeyFlags) {
        let plain: Data
        switch keyFlags {
        case .both:
            guard let even = keys[0], let odd = keys[1] else { return }
            plain = even + odd
        case .even, .odd:
            guard let key = keys[Self.slot(keyFlags)] else { return }
            plain = key
        }
        guard let wrapped = SrtCrypto.wrapKey(plain, with: keyEncryptingKey) else { return }

        let frame = KeyMaterialFrame(keyFlags: keyFlags, keyLength: keyLength, salt: salt, wrappedKey: wrapped)
        announcements[Self.announcementSlot(keyFlags)] = Announcement(material: frame.data,
                                                                    retries: Self.announcementRetries,
                                                                    lastSent: nil)
    }

    /// Key material due to go to the peer: a new announcement at once, then
    /// again every 1.5 RTT until it is echoed, ten times at most, as libsrt.
    public func keyMaterialToSend(now: UInt32, rttMicroseconds: UInt32) -> [Data] {
        let interval = UInt64(rttMicroseconds) * 3 / 2
        var due: [Data] = []

        for index in announcements.indices {
            guard var announcement = announcements[index], announcement.retries > 0 else { continue }
            if let last = announcement.lastSent, UInt64(SrtClock.elapsed(from: last, to: now)) < interval { continue }
            announcement.retries -= 1
            announcement.lastSent = now
            announcements[index] = announcement
            due.append(announcement.material)
        }
        return due
    }

    /// Sender: the peer echoed a KM. True if it was one we were waiting on.
    @discardableResult
    public func acknowledge(keyMaterialResponse response: Data) -> Bool {
        for index in announcements.indices where announcements[index]?.material == response {
            announcements[index] = nil
            return true
        }
        return false
    }

    /// Receiver: the peer's KMREQ after the handshake, carrying one key or
    /// two. On success the request itself is the KMRSP to echo. The key
    /// length is fixed for the life of the connection, as libsrt requires;
    /// the salt may change, in which case the KEK is derived again.
    public func install(keyMaterial request: Data) -> Result<Data, SrtEncryptionError> {

        guard let frame = KeyMaterialFrame(request) else {
            return .failure(.keyMaterialMalformed)
        }
        guard frame.cipher == KeyMaterialFrame.cipherAesCtr, frame.auth == 0 else {
            return .failure(.badCryptoMode)
        }
        guard frame.keyLength == keyLength else {
            return .failure(.keyLength)
        }

        var kek = keyEncryptingKey
        if frame.salt != salt {
            guard let derived = SrtCrypto.keyEncryptingKey(passphrase: passphrase, salt: frame.salt, keyLength: keyLength) else {
                return .failure(.badSecret)
            }
            kek = derived
        }
        guard let keys = SrtCrypto.unwrapKey(frame.wrappedKey, with: kek),
              keys.count == keyLength * frame.keyFlags.keyCount else {
            return .failure(.badSecret)
        }

        salt = frame.salt
        keyEncryptingKey = kek
        Self.place(keys, from: frame, into: &self.keys)
        installs += 1
        return .success(request)
    }

    /// Unwrapped keys go to the slots the KM's KK bits name.
    private static func place(_ keys: Data, from frame: KeyMaterialFrame, into slots: inout [Data?]) {
        let length = frame.keyLength
        switch frame.keyFlags {
        case .both:
            slots[0] = Data(keys.prefix(length))
            slots[1] = Data(keys.suffix(length))
        case .even:
            slots[0] = Data(keys.prefix(length))
        case .odd:
            slots[1] = Data(keys.prefix(length))
        }
    }

    /// Which key slot a parity names.
    private static func slot(_ flags: KeyFlags) -> Int { flags == .odd ? 1 : 0 }

    /// libsrt files a KM by KK >> 1: even alone in 0, odd or both in 1.
    private static func announcementSlot(_ flags: KeyFlags) -> Int { Int(flags.rawValue >> 1) }

    // MARK: Payload

    /// Seals with the active key and counts the packet against its period.
    public func encrypt(_ payload: Data, sequence: UInt32) -> Data? {
        guard let key = keys[Self.slot(activeKey)] else { return nil }
        packetsUnderActiveKey &+= 1
        return SrtCrypto.aesCtr(key: key, iv: SrtCrypto.counterBlock(salt: salt, sequence: sequence), data: payload)
    }

    /// Opens with the key the packet's KK bits name; nil if we do not hold it.
    public func decrypt(_ payload: Data, sequence: UInt32, keyFlags: KeyFlags = .even) -> Data? {
        guard keyFlags != .both, let key = keys[Self.slot(keyFlags)] else { return nil }
        return SrtCrypto.aesCtr(key: key, iv: SrtCrypto.counterBlock(salt: salt, sequence: sequence), data: payload)
    }
}
