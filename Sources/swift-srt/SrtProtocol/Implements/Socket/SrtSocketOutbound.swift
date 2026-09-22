//
//  SrtSocketOutbound.swift
//  swift-srt
//

import Foundation

/// The way into a socket for data to send. Sendable, so a capture thread can
/// hold it; each payload is queued as an event and packetized by whichever
/// task owns the socket, so the engine stays single-owner.
public struct SrtSocketOutbound: Sendable {

    private let inbox: AsyncStream<SrtSocketEvent>.Continuation

    init(inbox: AsyncStream<SrtSocketEvent>.Continuation) {
        self.inbox = inbox
    }

    /// Queues one payload. For MPEG-TS this is one or more whole 188 byte
    /// packets, at most the negotiated payload size per call.
    public func send(_ payload: Data) {
        inbox.yield(.send(payload))
    }
}
