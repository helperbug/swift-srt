//
//  SrtListenerContext.swift
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

public class SrtListenerContext {
    
    /// This listener's own socket ID, which it advertises to the caller.
    let srtSocketID: UInt32

    /// Socket ID of the caller, taken from the induction request. Every response
    /// is addressed to it.
    let peerSocketID: UInt32

    let initialPacketSequenceNumber: UInt32
    let synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool

    /// Shared secret, if this side requires encryption.
    let passphrase: String?

    /// The stream's keys once the exchange has succeeded.
    private(set) var encryption: SrtEncryption?

    /// Why the exchange failed, if it did.
    private(set) var encryptionError: SrtEncryptionError?
    /// Accumulated by the states while an event is handled, then returned.
    private var actions: [HandshakeAction] = []

    /// The current handshake phase, observable so callers and tests can tell an
    /// established connection from one still negotiating.
    var state: SrtListenerStates { _state.name }

    private var _state: SrtListenerState
    
    init(
        srtSocketID: UInt32,
        peerSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        passphrase: String? = nil
    ) {
        self.srtSocketID = srtSocketID
        self.peerSocketID = peerSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self.passphrase = passphrase
        self._state = StrListenerInducedState()
        
    }

    /// Sending from `init` meant the reply could arrive before the caller had a
    /// reference to hand it to. Starting is now a separate, explicit step.
    func start() -> [HandshakeAction] {
        _state.auto(self)
        return drain()
    }

    /// Parameters the caller asked for in its conclusion request.
    private(set) var streamId: String?
    /// The peer's initial packet sequence number, from its conclusion message.
    private(set) var peerInitialSequence: UInt32?
    private(set) var srtVersion: UInt32?
    private(set) var srtFlags: UInt32?
    private(set) var receiverTsbpdDelay: UInt16?
    private(set) var senderTsbpdDelay: UInt16?

    /// Record what the caller requested so the socket can be built from it.
    func apply(handshake: SrtHandshake) {

        self.streamId = handshake.streamId
        self.peerInitialSequence = handshake.initialPacketSequenceNumber
        self.srtVersion = handshake.srtVersion
        self.srtFlags = handshake.srtFlags
        self.receiverTsbpdDelay = handshake.receiverTsbpdDelay
        self.senderTsbpdDelay = handshake.senderTsbpdDelay

    }

    func handleHandshake(handshake: SrtHandshake) -> [HandshakeAction] {
        _state.handleHandshake(self, handshake: handshake)
        return drain()
    }

    func install(encryption: SrtEncryption?) {
        self.encryption = encryption
    }

    func fail(encryption error: SrtEncryptionError) {
        self.encryptionError = error
    }

    func send(_ packet: SrtPacket, _ contents: Data) {
        actions.append(.send(packet, contents))
    }

    func socketCreated(_ engine: SrtSocketContext) {
        actions.append(.socketCreated(engine))
    }

    private func drain() -> [HandshakeAction] {
        defer { actions.removeAll() }
        return actions
    }
    
    @discardableResult
    func set(newState: SrtListenerStates) -> SrtListenerState {
        
        self._state = newState.instance
        return self._state
        
    }
    
}
