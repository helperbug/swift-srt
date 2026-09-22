//
//  SrtRendezvousContext.swift
//  swift-srt
//
//  Rendezvous handshake: both sides call each other at once, which is what
//  gets a connection through a NAT on both ends. Each side waves with a
//  random cookie; the larger cookie becomes the initiator and runs the
//  caller's conclusion exchange, the smaller answers like a listener, and
//  the initiator closes with an agreement so the responder knows it landed.
//

import Foundation

public final class SrtRendezvousContext {

    public enum Role: Sendable { case undecided, initiator, responder }

    let srtSocketID: UInt32
    let initialPacketSequenceNumber: UInt32
    let peerIpAddress: Data
    let passphrase: String?
    let streamId: String?

    /// Ours, for the cookie contest. Regenerated on a tie.
    private(set) var cookie: UInt32

    private(set) var peerSocketID: UInt32 = 0
    private(set) var peerInitialSequence: UInt32?
    private(set) var role: Role = .undecided
    private(set) var encryption: SrtEncryption?
    private(set) var encryptionError: SrtEncryptionError?
    private(set) var srtVersion: UInt32?
    private(set) var srtFlags: UInt32?
    private(set) var receiverTsbpdDelay: UInt16?
    private(set) var senderTsbpdDelay: UInt16?

    var state: SrtRendezvousStates { _state.name }
    private var _state: SrtRendezvousState = RendezvousWavingState()

    /// The last packet sent, for retransmission while waiting.
    private var lastSent: (SrtPacket, Data)?
    private var actions: [HandshakeAction] = []

    init(srtSocketID: UInt32, initialPacketSequenceNumber: UInt32, peerIpAddress: Data, passphrase: String? = nil, streamId: String? = nil) {
        self.srtSocketID = srtSocketID
        self.initialPacketSequenceNumber = initialPacketSequenceNumber
        self.peerIpAddress = peerIpAddress
        self.passphrase = passphrase
        self.streamId = streamId
        self.cookie = UInt32.random(in: 1...UInt32.max)
    }

    func start() -> [HandshakeAction] {
        _state.auto(self)
        return drain()
    }

    /// Nothing heard in a while: send the last thing again.
    func retry() -> [HandshakeAction] {
        guard _state.name != .active, _state.name != .shutdown, let lastSent else { return [] }
        actions.append(.send(lastSent.0, lastSent.1))
        return drain()
    }

    func handleHandshake(handshake: SrtHandshake) -> [HandshakeAction] {
        _state.handleHandshake(self, handshake: handshake)
        return drain()
    }

    // MARK: State support

    @discardableResult
    func set(newState: SrtRendezvousStates) -> SrtRendezvousState {
        _state = newState.instance
        return _state
    }

    func send(_ packet: SrtPacket, _ contents: Data) {
        lastSent = (packet, contents)
        actions.append(.send(packet, contents))
    }

    func socketCreated(_ engine: SrtSocketContext) {
        actions.append(.socketCreated(engine))
    }

    func newCookie() { cookie = UInt32.random(in: 1...UInt32.max) }

    /// The peer went first with a conclusion: it leads, we answer.
    func assumeResponder(to peer: SrtHandshake) {
        peerSocketID = peer.srtSocketID
        role = .responder
    }

    func decide(peer: SrtHandshake) -> Role {
        peerSocketID = peer.srtSocketID
        peerInitialSequence = peer.initialPacketSequenceNumber
        /// libsrt: the difference as a signed 32-bit number decides.
        let difference = Int32(bitPattern: cookie &- peer.synCookie)
        role = difference > 0 ? .initiator : (difference < 0 ? .responder : .undecided)
        return role
    }

    func apply(handshake: SrtHandshake) {
        peerInitialSequence = handshake.initialPacketSequenceNumber
        srtVersion = handshake.srtVersion
        srtFlags = handshake.srtFlags
        receiverTsbpdDelay = handshake.receiverTsbpdDelay
        senderTsbpdDelay = handshake.senderTsbpdDelay
    }

    func install(encryption: SrtEncryption?) { self.encryption = encryption }
    func fail(encryption error: SrtEncryptionError) { self.encryptionError = error }

    private func drain() -> [HandshakeAction] {
        defer { actions.removeAll() }
        return actions
    }

    /// The socket both roles end up with.
    func makeSocket() -> SrtSocketContext {
        let socket = SrtSocketContext(encrypted: encryption != nil, socketId: srtSocketID, peerSocketId: peerSocketID, synCookie: cookie)
        socket.initialPacketSequenceNumber = peerInitialSequence ?? initialPacketSequenceNumber
        socket.ownInitialSequenceNumber = initialPacketSequenceNumber
        socket.srtVersion = srtVersion
        socket.srtFlags = srtFlags
        socket.receiverTsbpdDelay = receiverTsbpdDelay
        socket.senderTsbpdDelay = senderTsbpdDelay
        socket.streamId = streamId
        socket.encryption = encryption
        return socket
    }
}

// MARK: States

public enum SrtRendezvousStates: Sendable {
    case waving, initiating, responding, active, shutdown

    var instance: SrtRendezvousState {
        switch self {
        case .waving: return RendezvousWavingState()
        case .initiating: return RendezvousInitiatingState()
        case .responding: return RendezvousRespondingState()
        case .active: return RendezvousActiveState()
        case .shutdown: return RendezvousShutdownState()
        }
    }
}

protocol SrtRendezvousState {
    var name: SrtRendezvousStates { get }
    func auto(_ context: SrtRendezvousContext)
    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake)
}

extension SrtRendezvousState {
    func auto(_ context: SrtRendezvousContext) { }
    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) {
        print("Rendezvous: ignoring \(handshake.handshakeType) in state \(name)")
    }
}

/// Wave until the peer waves back, then let the cookies decide who leads.
struct RendezvousWavingState: SrtRendezvousState {
    let name: SrtRendezvousStates = .waving

    func auto(_ context: SrtRendezvousContext) {
        let wave = SrtHandshake.makeWaveAHand(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            cookie: context.cookie,
            peerIpAddress: context.peerIpAddress,
            encryptionField: context.passphrase == nil ? 0 : 2
        )
        context.send(SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data()), wave.data)
    }

    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) {
        switch handshake.handshakeType {
        case .waveAHand:
            switch context.decide(peer: handshake) {
            case .initiator:
                context.set(newState: .initiating).auto(context)
            case .responder:
                /// Wave once more so the peer sees our cookie if it missed it,
                /// then wait for its conclusion.
                auto(context)
                context.set(newState: .responding)
            case .undecided:
                /// A tie: new cookie, wave again.
                context.newCookie()
                auto(context)
            }

        case .conclusion:
            /// The peer saw our wave and moved on before we saw its wave. libsrt
            /// keeps its cookie on every packet, so the contest still runs; a
            /// bare conclusion with no cookie means the peer decided it leads.
            switch handshake.synCookie == 0 ? SrtRendezvousContext.Role.responder : context.decide(peer: handshake) {
            case .initiator:
                context.set(newState: .initiating).auto(context)
            case .responder, .undecided:
                context.assumeResponder(to: handshake)
                context.set(newState: .responding).handleHandshake(context, handshake: handshake)
            }

        default:
            break
        }
    }
}

/// We lead: send the conclusion with our extensions, wait for the answer,
/// then agree.
struct RendezvousInitiatingState: SrtRendezvousState {
    let name: SrtRendezvousStates = .initiating

    func auto(_ context: SrtRendezvousContext) {
        var extensions: [HandshakeExtensionTypes: Data] = [
            .handshakeRequest: HandshakeExtensionMessage(
                srtVersion: SrtHandshake.srtLibraryVersion, srtFlags: SrtHandshake.defaultSrtFlags,
                receiverTsbpdDelay: SrtHandshake.defaultTsbpdDelay, senderTsbpdDelay: SrtHandshake.defaultTsbpdDelay).data
        ]
        if let streamId = context.streamId, !streamId.isEmpty {
            extensions[.streamId] = StrCallerInductedState.encodeStreamId(streamId)
        }
        var encryptionField: UInt16 = 0
        if let passphrase = context.passphrase {
            /// Made once. A repeated conclusion carries the same key material,
            /// so the responder's echo of either copy still matches.
            if context.encryption == nil {
                guard let encryption = try? SrtEncryption(passphrase: passphrase) else {
                    context.fail(encryption: .passphraseLength)
                    context.set(newState: .shutdown)
                    return
                }
                context.install(encryption: encryption)
            }
            extensions[.keyMaterialRequest] = context.encryption!.keyMaterial
            encryptionField = context.encryption!.encryptionField
        }

        /// Our cookie rides on every rendezvous packet: libsrt runs the contest
        /// on whichever of ours it holds, and a zero there reads as unresolved.
        let conclusion = SrtHandshake.makeConclusionRequest(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            synCookie: context.cookie,
            peerIpAddress: context.peerIpAddress,
            extensions: extensions,
            encryptionField: encryptionField
        )
        context.send(SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data()), conclusion.data)
    }

    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) {
        switch handshake.handshakeType {
        case .waveAHand:
            /// The peer missed our conclusion; send it again.
            auto(context)

        case .conclusion where handshake.isConclusionResponse:
            context.apply(handshake: handshake)
            if let encryption = context.encryption {
                guard let response = handshake.keyMaterialResponse,
                      case .success = encryption.accept(keyMaterialResponse: response) else {
                    context.fail(encryption: .peerRejected(.badSecret))
                    context.set(newState: .shutdown)
                    return
                }
            }
            /// Agreement tells the responder its answer arrived.
            let agreement = SrtHandshake.makeAgreement(
                srtSocketID: context.srtSocketID,
                initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                peerIpAddress: context.peerIpAddress
            )
            context.set(newState: .active)
            context.socketCreated(context.makeSocket())
            context.send(SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data()), agreement.data)

        default:
            break
        }
    }
}

/// The peer leads: answer its conclusion, and connect when it agrees.
struct RendezvousRespondingState: SrtRendezvousState {
    let name: SrtRendezvousStates = .responding

    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) {
        switch handshake.handshakeType {
        case .waveAHand:
            /// Still waving: our wave was lost. Wave back.
            RendezvousWavingState().auto(context)

        case .conclusion where handshake.extensions[.handshakeRequest] != nil:
            context.apply(handshake: handshake)

            if let request = handshake.keyMaterialRequest {
                switch SrtEncryption.respond(toKeyMaterial: request, passphrase: context.passphrase) {
                case .success(let encryption): context.install(encryption: encryption)
                case .failure(let error): context.fail(encryption: error)
                }
            } else if context.passphrase != nil {
                context.fail(encryption: .noSecret)
            }

            let keyMaterialResponse: Data?
            if let encryption = context.encryption {
                keyMaterialResponse = encryption.keyMaterial
            } else if let error = context.encryptionError {
                keyMaterialResponse = SrtEncryption.refusal(error)
            } else {
                keyMaterialResponse = nil
            }

            let response = SrtHandshake.makeConclusionResponse(
                srtSocketID: context.srtSocketID,
                initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                synCookie: context.cookie,
                peerIpAddress: context.peerIpAddress,
                keyMaterialResponse: keyMaterialResponse,
                encryptionField: context.encryption?.encryptionField ?? (context.passphrase == nil ? 0 : 2)
            )
            context.send(SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data()), response.data)

            if context.encryptionError != nil {
                context.set(newState: .shutdown)
            }

        case .agreement:
            guard context.encryptionError == nil else { return }
            context.set(newState: .active)
            context.socketCreated(context.makeSocket())

        case .conclusion where handshake.synCookie != 0 && context.decide(peer: handshake) == .initiator:
            /// A conclusion with no request: the peer is waiting on us to lead.
            context.set(newState: .initiating).auto(context)

        default:
            break
        }
    }
}

struct RendezvousActiveState: SrtRendezvousState {
    let name: SrtRendezvousStates = .active
    /// Late duplicates of the exchange are absorbed.
    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) { }
}

struct RendezvousShutdownState: SrtRendezvousState {
    let name: SrtRendezvousStates = .shutdown
    func handleHandshake(_ context: SrtRendezvousContext, handshake: SrtHandshake) { }
}
