//
//  SrtCrypto.swift
//  swift-srt
//
//  The primitives SRT's encryption is built from, as libsrt's haicrypt uses
//  them: PBKDF2-HMAC-SHA1 for the key-encrypting key, RFC 3394 AES key wrap
//  for the stream key, AES-CTR for payload, and the counter block layout that
//  ties a packet's sequence number to its keystream.
//

import CommonCrypto
import Foundation
import Security

public enum SrtCrypto {

    /// haicrypt: PBKDF2 over the LAST eight bytes of the 16 byte salt, 2048
    /// rounds, output as long as the stream key.
    public static let pbkdf2SaltLength = 8
    public static let pbkdf2Iterations: UInt32 = 2048
    public static let saltLength = 16
    public static let keyWrapOverhead = 8
    public static let passphraseMinimum = 10
    public static let passphraseMaximum = 79

    public static func pbkdf2Sha1(passphrase: Data, salt: Data, iterations: UInt32, keyLength: Int) -> Data? {
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { out -> Int32 in
            passphrase.withUnsafeBytes { pass -> Int32 in
                salt.withUnsafeBytes { salt -> Int32 in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pass.bindMemory(to: CChar.self).baseAddress, passphrase.count,
                                         salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), iterations,
                                         out.bindMemory(to: UInt8.self).baseAddress, keyLength)
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    /// The key-encrypting key for a stream: the passphrase and the tail of the salt.
    public static func keyEncryptingKey(passphrase: String, salt: Data, keyLength: Int) -> Data? {
        guard salt.count >= pbkdf2SaltLength else { return nil }
        let tail = salt.suffix(pbkdf2SaltLength)
        return pbkdf2Sha1(passphrase: Data(passphrase.utf8), salt: Data(tail), iterations: pbkdf2Iterations, keyLength: keyLength)
    }

    /// RFC 3394 with the default initial value; output is the key plus 8 bytes.
    public static func wrapKey(_ key: Data, with kek: Data) -> Data? {
        var wrapped = Data(count: key.count + keyWrapOverhead)
        var wrappedLength = wrapped.count
        let status = wrapped.withUnsafeMutableBytes { out -> Int32 in
            kek.withUnsafeBytes { kek -> Int32 in
                key.withUnsafeBytes { key -> Int32 in
                    CCSymmetricKeyWrap(CCWrappingAlgorithm(kCCWRAPAES),
                                       CCrfc3394_iv, CCrfc3394_ivLen,
                                       kek.bindMemory(to: UInt8.self).baseAddress, kek.count,
                                       key.bindMemory(to: UInt8.self).baseAddress, key.count,
                                       out.bindMemory(to: UInt8.self).baseAddress, &wrappedLength)
                }
            }
        }
        return status == kCCSuccess ? wrapped.prefix(wrappedLength) : nil
    }

    /// Nil when the integrity check fails, which is how a wrong passphrase shows up.
    public static func unwrapKey(_ wrapped: Data, with kek: Data) -> Data? {
        guard wrapped.count > keyWrapOverhead else { return nil }
        var key = Data(count: wrapped.count - keyWrapOverhead)
        var keyLength = key.count
        let status = key.withUnsafeMutableBytes { out -> Int32 in
            kek.withUnsafeBytes { kek -> Int32 in
                wrapped.withUnsafeBytes { wrapped -> Int32 in
                    CCSymmetricKeyUnwrap(CCWrappingAlgorithm(kCCWRAPAES),
                                         CCrfc3394_iv, CCrfc3394_ivLen,
                                         kek.bindMemory(to: UInt8.self).baseAddress, kek.count,
                                         wrapped.bindMemory(to: UInt8.self).baseAddress, wrapped.count,
                                         out.bindMemory(to: UInt8.self).baseAddress, &keyLength)
                }
            }
        }
        return status == kCCSuccess ? key.prefix(keyLength) : nil
    }

    /// AES-CTR is its own inverse.
    public static func aesCtr(key: Data, iv: Data, data: Data) -> Data? {
        guard iv.count == 16, [16, 24, 32].contains(key.count) else { return nil }

        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { key -> Int32 in
            iv.withUnsafeBytes { iv -> Int32 in
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                                        CCPadding(ccNoPadding), iv.baseAddress, key.baseAddress, key.count,
                                        nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
            }
        }
        guard created == kCCSuccess, let cryptor else { return nil }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: data.count + 16)
        var moved = 0
        let status = output.withUnsafeMutableBytes { out -> Int32 in
            data.withUnsafeBytes { input -> Int32 in
                CCCryptorUpdate(cryptor, input.baseAddress, data.count, out.baseAddress, out.count, &moved)
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(moved)
    }

    /// The per-packet counter block, from hcrypt_SetCtrIV: sixteen zero bytes,
    /// the packet index at bytes 10-13 in network byte order, bytes 0-13 XORed
    /// with the salt, block counter in the last two. Verified against libsrt:
    /// the little-endian reading of the source decrypted to noise.
    public static func counterBlock(salt: Data, sequence: UInt32) -> Data {
        var iv = Data(count: 16)
        iv[10] = UInt8((sequence >> 24) & 0xFF)
        iv[11] = UInt8((sequence >> 16) & 0xFF)
        iv[12] = UInt8((sequence >> 8) & 0xFF)
        iv[13] = UInt8(sequence & 0xFF)
        for index in 0..<min(14, salt.count) {
            iv[index] ^= salt[salt.startIndex + index]
        }
        return iv
    }

    public static func randomBytes(_ count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes
    }
}
