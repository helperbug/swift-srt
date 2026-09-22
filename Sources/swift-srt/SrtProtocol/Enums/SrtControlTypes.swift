//
//  ControlTypes
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

public enum ControlTypes: UInt16, Sendable {
    case handshake = 0x0000
    case keepAlive = 0x0001
    case acknowledgement = 0x0002
    case negativeAcknowledgement = 0x0003
    case congestionWarning = 0x0004
    case shutdown = 0x0005
    case ackack = 0x0006
    case dropRequest = 0x0007
    case peerError = 0x0008
    case userDefined = 0x7FFF
    case none = 0xFFFF
    
    var asField: UInt32 {
        return UInt32(self.rawValue) << 16
    }
}

