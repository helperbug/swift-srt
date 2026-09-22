//
//  SrtCallerContext
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

public class SrtCallerContext {
    
    let srtSocketID: UInt32

    /// Socket ID of the listener, learned from the induction response. Every packet
    /// after induction is addressed to it.
    var peerSocketID: UInt32 = 0

    let initialPacketSequenceNumber: UInt32
    var synCookie: UInt32
    let peerIpAddress: Data
    let encrypted: Bool

    /// Shared secret, if this side requires encryption.
    let passphrase: String?

    /// The stream's keys once the exchange has succeeded.
    private(set) var encryption: SrtEncryption?

    /// Why the exchange failed, if it did.
    private(set) var encryptionError: SrtEncryptionError?

    /// Path the caller asks the listener for, sent as SRT_CMD_SID.
    let streamId: String?

    /// Accumulated by the states while an event is handled, then returned.
    private var actions: [HandshakeAction] = []

    /// Parameters the listener agreed to in its conclusion response.
    /// The peer's initial packet sequence number, from its conclusion message.
    private(set) var peerInitialSequence: UInt32?
    private(set) var srtVersion: UInt32?
    private(set) var srtFlags: UInt32?
    private(set) var receiverTsbpdDelay: UInt16?
    private(set) var senderTsbpdDelay: UInt16?

    /// The current handshake phase, observable so callers and tests can tell an
    /// established connection from one still negotiating.
    var state: SrtCallerStates { _state.name }

    private var _state: SrtCallerState
    
    init(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data,
        encrypted: Bool,
        passphrase: String? = nil,
        streamId: String? = nil
    ) {

        self.srtSocketID = srtSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.synCookie = synCookie
        self.peerIpAddress = peerIpAddress
        self.encrypted = encrypted
        self.passphrase = passphrase
        self.streamId = streamId
        self._state = StrCallerStartState()
        
    }

    /// Sending from `init` meant the reply could arrive before the caller had a
    /// reference to hand it to. Starting is now a separate, explicit step.
    func start() -> [HandshakeAction] {
        _state.auto(self)
        return drain()
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

    /// Record what the listener agreed to so the socket can be built from it.
    func apply(handshake: SrtHandshake) {

        self.peerInitialSequence = handshake.initialPacketSequenceNumber
        self.srtVersion = handshake.srtVersion
        self.srtFlags = handshake.srtFlags
        self.receiverTsbpdDelay = handshake.receiverTsbpdDelay
        self.senderTsbpdDelay = handshake.senderTsbpdDelay

    }
    
    @discardableResult
    func set(newState: SrtCallerStates) -> SrtCallerState {
        
        self._state = newState.instance
        return self._state
        
    }
    
}
