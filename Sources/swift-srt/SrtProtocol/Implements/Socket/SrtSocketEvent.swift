//
//  SrtSocketEvent.swift
//  swift-srt
//

import Foundation

/// What a socket's owner pulls from its stream: packets from the wire, and
/// ticks from the connection's timer so time-driven work (ACKs, NAKs, TSBPD
/// release, too-late drops) happens even when nothing is arriving.
public enum SrtSocketEvent: Sendable {
    case packet(SrtPacket)
    /// The connection clock's reading when the tick fired.
    case tick(UInt32)
    /// Application payload to packetize and send.
    case send(Data)
}
