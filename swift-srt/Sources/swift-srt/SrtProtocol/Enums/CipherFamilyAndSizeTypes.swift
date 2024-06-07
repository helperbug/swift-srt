//
//  CipherFamilyAndSizeTypes.swift
//
//
//  Created by Ben Waidhofer on 6/6/24.
//

import Foundation

enum CipherFamilyAndSizeTypes: Int {
    case noEncryptionAdvertised = 0
    case aes128 = 2
    case aes192 = 3
    case aes256 = 4

    var label: String {
        switch self {
        case .noEncryptionAdvertised:
            return "No Encryption Advertised"
        case .aes128:
            return "AES-128"
        case .aes192:
            return "AES-192"
        case .aes256:
            return "AES-256"
        }
    }
}
