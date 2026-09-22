//
//  ListenerStates.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation

public enum SrtPortListnerStates: Sendable {
    case none
    case ready
    case error
    
    public var label: String {
        switch self {
        case .none:
            return "None"
        case .error:
            return "Error"
        case .ready:
            return "Ready"
        }
    }
}
