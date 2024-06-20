//
//  AdaptationFieldControlTypes.swift
//
//
//  Created by Ben Waidhofer on 6/19/24.
//

import Foundation

public enum AdaptationFieldControlTypes: UInt8 {
    case reserved = 0x00
    case payloadOnly = 0x01
    case adaptationFieldOnly = 0x02
    case adaptationFieldFollowedByPayload = 0x03
}
