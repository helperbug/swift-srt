//
//  HandshakeAction.swift
//  swift-srt
//
//  What a handshake state machine wants done. The machines are pure: they
//  return these and the connection applies them, which keeps every side effect
//  in one place and keeps the machines trivially testable.
//

import Foundation

enum HandshakeAction {
    /// Put a packet on the wire.
    case send(SrtPacket, Data)
    /// The handshake completed; this engine now owns the socket's protocol state.
    case socketCreated(SrtSocketContext)
}
