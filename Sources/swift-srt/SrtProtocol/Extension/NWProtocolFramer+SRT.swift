//
//  NWProtocolFramer+SRT.swift
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
import Network

extension NWProtocolFramer.Message {
    convenience init(srtPacket: SrtPacket) {
        self.init(definition: SrtProtocolFramer.definition)
        
        self.srtPacket = srtPacket
    }

    var srtPacket: SrtPacket? {
        get {
            self["SrtPacket"] as? SrtPacket
        }
        set {
            self["SrtPacket"] = newValue
        }
    }

}

