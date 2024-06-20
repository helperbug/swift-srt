//
//  TransportScramblingControlTypes.swift
//
//
//  Created by Ben Waidhofer on 6/19/24.
//

import Foundation

public enum TransportScramblingControlTypes: UInt8 {
    case notScrambled = 0x00
    case reserved = 0x40
    case scrambledEvenKey = 0x80
    case scrambledOddKey = 0xC0
}
