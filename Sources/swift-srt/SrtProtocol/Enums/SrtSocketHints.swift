//
//  SrtSocketHints.swift
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

/// Represents the hints associated with an SRT socket.
public enum SrtSocketHints: Sendable {
    
    /// How many frames at 4k60fps using h.265 encoder.
    case hd4k265f60
    
    /// Recommended audio bitrate for high-fidelity streaming.
    case highFidelityAudio
    
    /// Maximum supported resolution for screen sharing based on current network conditions.
    case maxSupportedResolution
    
    /// Optimal settings for video conferencing, balancing quality and latency.
    case videoConferencing
    
}
