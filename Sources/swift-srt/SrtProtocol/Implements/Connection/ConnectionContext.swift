//
//  ConnectionContext.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  Portions of this project are based on the SRT protocol specification.
//  SRT is licensed under the Mozilla Public License, v. 2.0.
//  You may obtain a copy of the License at
//  https://github.com/Haivision/srt/blob/master/LICENSE
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import Network
import Synchronization

/// One UDP flow with the SRT framer attached. Reads every datagram on the
/// connection's queue, routes it by destination socket ID into that socket's
/// stream, and runs the handshake for packets that have no socket yet.
///
/// Mutable state lives in `Confined` behind a mutex. The lock is uncontended
/// on the hot path -- only the connection's own queue takes it -- and is held
/// for one lookup and one yield per data packet.
public final class ConnectionContext: SrtConnectionProtocol, Sendable {

    public let udpHeader: UdpHeader
    let connection: NWConnection
    let queue: DispatchQueue

    /// Timestamps on everything this connection sends, and RTT for its sockets.
    let clock = SrtClock()

    /// `UdpHeader.cookie` mixes in the wall clock at one-minute accuracy, so
    /// reading it twice can yield two different cookies. Mint it once.
    let synCookie: UInt32

    /// Required of every peer on this flow when set.
    let passphrase: String?

    private let logService: LogServiceProtocol
    private let managerService: SrtPortManagerServiceProtocol
    private let metricsService: SrtMetricsServiceProtocol

    /// Everything that changes after init.
    struct Confined {
        var sockets: [UInt32: SocketRoute] = [:]
        var pendingListener: SrtListenerContext?
        var pendingCaller: SrtCallerContext?
        var pendingRendezvous: SrtRendezvousContext?
        var rendezvousAttempts = 0
        var state: ConnectionState = ConnectionSetupState()

        /// A caller's handshake requested before the connection was ready.
        var callerRequest: (address: IPv4Address, streamId: String?)?

        /// A rendezvous requested before the connection was ready.
        var rendezvousRequest: (address: IPv4Address, streamId: String?)?

        /// Fires every SYN interval on the connection queue and ticks every socket.
        var ticker: DispatchSourceTimer?

        @discardableResult
        mutating func set(_ newState: ConnectionStates) -> ConnectionState {
            state = newState.state
            return state
        }
    }

    private let confined = Mutex(Confined())

    init(updHeader: UdpHeader,
         connection: NWConnection,
         queue: DispatchQueue? = nil,
         passphrase: String? = nil,
         logService: LogServiceProtocol,
         managerService: SrtPortManagerServiceProtocol,
         metricsService: SrtMetricsServiceProtocol) {

        self.connection = connection
        self.queue = queue ?? DispatchQueue(label: "srt.connection.\(updHeader.sourceIp):\(updHeader.sourcePort)", qos: .userInitiated)
        self.udpHeader = updHeader
        self.synCookie = updHeader.cookie
        self.passphrase = passphrase
        self.logService = logService
        self.managerService = managerService
        self.metricsService = metricsService
    }

    public static func make(isHost: Bool,
                            _ connection: NWConnection,
                            queue: DispatchQueue? = nil,
                            passphrase: String? = nil,
                            logService: LogServiceProtocol,
                            managerService: SrtPortManagerServiceProtocol,
                            metricsService: SrtMetricsServiceProtocol) -> ConnectionContext? {

        guard let udpHeader = connection.makeUdpHeader(isHost: isHost) else {
            return nil
        }

        let context = ConnectionContext(updHeader: udpHeader,
                                        connection: connection,
                                        queue: queue,
                                        passphrase: passphrase,
                                        logService: logService,
                                        managerService: managerService,
                                        metricsService: metricsService)

        /// Delivered on `queue`, since that is what the connection is started on.
        connection.stateUpdateHandler = { [weak context] state in
            context?.onStateChanged(state)
        }

        return context
    }

    // MARK: Public (take the lock)

    public func start() {
        let handoff: SrtSocket? = confined.withLock { confined in
            log("Starting Connection")
            guard confined.state.name == .setup else { return nil }
            let state = confined.state
            return state.auto(&confined, self)
        }
        if let handoff { managerService.addSocket(handoff) }
    }

    /// Begins a caller handshake toward `address`. If the connection is not up
    /// yet the request waits and the ready state starts it.
    public func handshake(address: IPv4Address, streamId: String? = nil) {
        let handoff: SrtSocket? = confined.withLock { confined in
            guard confined.pendingCaller == nil else { return nil }

            guard confined.state.name == .ready else {
                confined.callerRequest = (address, streamId)
                return nil
            }

            return beginCallerHandshake(address: address, streamId: streamId, &confined)
        }

        if let handoff { managerService.addSocket(handoff) }
    }

    /// Begins a rendezvous toward `address`; both sides do this at once.
    public func rendezvous(address: IPv4Address, streamId: String? = nil) {
        let handoff: SrtSocket? = confined.withLock { confined in
            guard confined.pendingRendezvous == nil else { return nil }
            guard confined.state.name == .ready else {
                confined.rendezvousRequest = (address, streamId)
                return nil
            }
            return beginRendezvous(address: address, streamId: streamId, &confined)
        }
        if let handoff { managerService.addSocket(handoff) }
    }

    func beginRendezvous(address: IPv4Address, streamId: String?, _ confined: inout Confined) -> SrtSocket? {
        let rendezvous = SrtRendezvousContext(
            srtSocketID: UInt32.random(in: 1...UInt32.max),
            initialPacketSequenceNumber: UInt32.random(in: 0...SrtSequence.maximum),
            peerIpAddress: address.to16bytes(),
            passphrase: passphrase,
            streamId: streamId
        )
        confined.pendingRendezvous = rendezvous
        confined.rendezvousRequest = nil
        confined.rendezvousAttempts = 0
        scheduleRendezvousRetry()
        return apply(rendezvous.start(), to: &confined, clearingCaller: false)
    }

    /// Rendezvous packets are resent every 250 ms until the peer answers,
    /// since both sides may start before the other is listening.
    private func scheduleRendezvousRetry() {
        queue.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard let self else { return }
            let handoff: SrtSocket? = confined.withLock { confined in
                guard let rendezvous = confined.pendingRendezvous else { return nil }
                confined.rendezvousAttempts += 1
                guard confined.rendezvousAttempts <= 40 else {
                    log("Rendezvous: no answer after 10 s, giving up")
                    confined.pendingRendezvous = nil
                    return nil
                }
                scheduleRendezvousRetry()
                return apply(rendezvous.retry(), to: &confined, clearingCaller: false)
            }
            if let handoff { managerService.addSocket(handoff) }
        }
    }

    /// Adopts a connection that was started elsewhere and is already ready --
    /// the caller path, where the local endpoint is only known after connect.
    public func adoptReady() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.onStateChanged(state)
        }
        let handoff: SrtSocket? = confined.withLock { confined in
            confined.set(.ready).auto(&confined, self)
        }
        if let handoff { managerService.addSocket(handoff) }
    }

    public func cancel() {
        guard connection.state != .cancelled else { return }
        connection.forceCancel()
    }

    public func shutdown() {
        confined.withLock { confined in
            let destination = confined.sockets.values.first?.peerSocketId ?? 0
            let packet = SrtPacket(field1: ControlTypes.shutdown.asField, socketID: destination, contents: Data())
            send(header: packet, contents: Data())
            notifyClosed(&confined)
        }
    }

    public var connectionState: ConnectionStates {
        confined.withLock { $0.state.name }
    }

    public var socketIds: [UInt32] {
        confined.withLock { Array($0.sockets.keys) }
    }

    // MARK: Queue callbacks (take the lock)

    func onStateChanged(_ state: NWConnection.State) {
        let handoff: SrtSocket? = confined.withLock { confined in
            let current = confined.state
            return current.onStateChanged(&confined, self, state: state)
        }
        if let handoff { managerService.addSocket(handoff) }
    }

    /// Hot path. A packet for a known socket is one lookup and one yield; the
    /// socket's owner does everything else.
    private func route(_ packet: SrtPacket) {

        let handoff: SrtSocket? = confined.withLock { confined in

            if let route = confined.sockets[packet.destinationSocketID] {

                /// Shutdown changes the socket table, which lives here.
                if !packet.isData, let control = ControlPacketFrame(packet.data),
                   control.controlType == ControlTypes.shutdown.rawValue {
                    closeSocket(id: packet.destinationSocketID, &confined)
                    return nil
                }

                route.inbox.yield(.packet(packet))
                return nil
            }

            /// No socket: only a handshake is meaningful. Anything else addressed
            /// to an unknown socket is dropped, so a stray packet cannot touch a
            /// stream it was not sent to.
            guard !packet.isData,
                  let control = ControlPacketFrame(packet.data),
                  control.controlType == ControlTypes.handshake.rawValue else {
                return nil
            }

            guard let handshake = SrtHandshake(data: packet.contents) else {
                log("Dropping unparseable handshake, \(packet.contents.count) bytes, dst \(packet.destinationSocketID)")
                return nil
            }

            log("Handshake in: \(handshake.handshakeType) v\(handshake.hsVersion.rawValue) ext 0x\(String(handshake.extensionField, radix: 16)) from socket \(handshake.srtSocketID) to \(packet.destinationSocketID), cookie \(handshake.synCookie), exts \(handshake.extensions.keys.map(\.label))")

            return handleHandshake(handshake, &confined)
        }

        /// The subscriber's handler runs outside the lock. The route was
        /// registered inside it, and the queue is serial, so the first data
        /// packet cannot overtake this.
        if let handoff { managerService.addSocket(handoff) }
    }

    // MARK: Lock-free (safe to call while the lock is held)

    /// `NWConnection` is thread-safe and nothing here touches confined state.
    ///
    /// Only the first 16 bytes of `header` go on the wire, so a frame that
    /// carries its own payload cannot send it twice. Control packets get a
    /// body of at least four bytes, aligned to four: libsrt pads its own
    /// "empty" control packets that way and rejects ones that are not.
    func send(header: SrtPacket, contents: Data) {

        guard connection.state == .ready else {
            log("ignoring send in state \(connection.state)")
            return
        }

        let stamped = SrtPacket(data: header.data.prefix(16)).stamped(clock.now)

        var body = contents
        if !stamped.isData {
            let padded = max(4, (body.count + 3) / 4 * 4)
            if padded > body.count {
                body.append(Data(repeating: 0, count: padded - body.count))
            }
        }

        let message = NWProtocolFramer.Message(srtPacket: stamped)
        let context = NWConnection.ContentContext(identifier: "srt", metadata: [message])

        connection.send(content: body, contentContext: context, isComplete: true, completion: .idempotent)
    }

    /// Re-armed after every message. The completion runs later on `queue`, so
    /// it takes the lock fresh; it is never re-entered.
    func receiveNextMessage() {

        connection.receiveMessage { [weak self] data, context, _, error in

            guard let self else { return }

            if let error {
                self.log("receive failed: \(error)")
                return
            }

            if let context,
               let message = context.protocolMetadata(definition: SrtProtocolFramer.definition) as? NWProtocolFramer.Message,
               let packet = message.srtPacket,
               data != nil {
                self.route(packet)
            }

            self.receiveNextMessage()
        }
    }

    func log(_ message: String) {
        logService.log("🛜", "Connection", message)
    }

    /// The SYN-interval timer. Runs on the connection queue, takes the lock
    /// only when it fires, and ticks every registered socket.
    func makeTicker() -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = clock.now
            confined.withLock { confined in
                for route in confined.sockets.values {
                    route.inbox.yield(.tick(now))
                }
            }
        }
        timer.resume()
        return timer
    }

    // MARK: Confined (call only with the lock held)

    /// Tells the manager this flow is gone. The manager owns the registry, and
    /// it lives on the main actor.
    func notifyClosed(_ confined: inout Confined) {
        confined.ticker?.cancel()
        confined.ticker = nil
        for route in confined.sockets.values {
            route.close()
        }
        confined.sockets.removeAll()

        let header = udpHeader
        let manager = managerService
        Task { @MainActor in manager.removeConnection(header: header) }
    }

    private func closeSocket(id: UInt32, _ confined: inout Confined) {
        confined.sockets[id]?.close()
        confined.sockets[id] = nil

        if confined.sockets.isEmpty {
            log("All sockets closed, cancelling connection")
            cancel()
            notifyClosed(&confined)
        } else {
            log("Socket \(id) shutdown, remaining sockets: \(confined.sockets.count)")
        }
    }

    func beginCallerHandshake(address: IPv4Address, streamId: String?, _ confined: inout Confined) -> SrtSocket? {

        /// Socket ID 0 is reserved to mean "connection request", so never pick it.
        let caller = SrtCallerContext(
            srtSocketID: UInt32.random(in: 1...UInt32.max),
            initialPacketSequenceNumber: UInt32.random(in: 0...SrtSequence.maximum),
            synCookie: 0,
            peerIpAddress: address.to16bytes(),
            encrypted: passphrase != nil,
            passphrase: passphrase,
            streamId: streamId
        )

        /// Assign before starting: the response can arrive as soon as the
        /// request goes out, and it has to find the caller here.
        confined.pendingCaller = caller
        confined.callerRequest = nil
        return apply(caller.start(), to: &confined, clearingCaller: true)
    }

    private func handleHandshake(_ handshake: SrtHandshake, _ confined: inout Confined) -> SrtSocket? {

        if let rendezvous = confined.pendingRendezvous {
            let handoff = apply(rendezvous.handleHandshake(handshake: handshake), to: &confined, clearingCaller: false)
            if rendezvous.state == .active || rendezvous.state == .shutdown {
                confined.pendingRendezvous = nil
            }
            return handoff
        }

        if let pendingListener = confined.pendingListener {
            return apply(pendingListener.handleHandshake(handshake: handshake), to: &confined, clearingCaller: false)
        }

        if let pendingCaller = confined.pendingCaller {
            return apply(pendingCaller.handleHandshake(handshake: handshake), to: &confined, clearingCaller: true)
        }

        guard handshake.isInductionRequest else {
            log("Unexpected handshake with no negotiation in progress")
            return nil
        }

        guard let peerIpAddress = udpHeader.sourceIp.ipStringToData else {
            log("Cannot parse peer address \(udpHeader.sourceIp)")
            return nil
        }

        /// The listener answers with a socket ID of its own; the caller's ID
        /// from the induction request becomes the destination for everything
        /// we send back.
        /// Our ISN goes in our responses; the peer's arrives with its conclusion.
        let listener = SrtListenerContext(
            srtSocketID: UInt32.random(in: 1...UInt32.max),
            peerSocketID: handshake.srtSocketID,
            initialPacketSequenceNumber: UInt32.random(in: 0...SrtSequence.maximum),
            synCookie: synCookie,
            peerIpAddress: peerIpAddress,
            encrypted: passphrase != nil,
            passphrase: passphrase
        )

        /// Assign before starting, so the conclusion request finds it here.
        confined.pendingListener = listener
        return apply(listener.start(), to: &confined, clearingCaller: false)
    }

    /// Carries out what a handshake machine asked for. A completed handshake
    /// registers its route here and returns the socket for handoff.
    private func apply(_ actions: [HandshakeAction], to confined: inout Confined, clearingCaller: Bool) -> SrtSocket? {

        var handoff: SrtSocket?

        for action in actions {
            switch action {
            case .send(let packet, let contents):
                if let handshake = SrtHandshake(data: contents) {
                    log("Handshake out: \(handshake.handshakeType) v\(handshake.hsVersion.rawValue) enc \(handshake.encryptionField) ext 0x\(String(handshake.extensionField, radix: 16)) as socket \(handshake.srtSocketID) to \(packet.destinationSocketID), cookie \(handshake.synCookie), exts \(handshake.extensions.keys.sorted { $0.rawValue < $1.rawValue }.map { "\($0.label)(\(handshake.extensions[$0]!.count))" })")
                }
                send(header: packet, contents: contents)

            case .socketCreated(let engine):
                let (events, inbox) = AsyncStream<SrtSocketEvent>.makeStream(bufferingPolicy: .bufferingNewest(4096))

                engine.clock = clock
                engine.activate()

                let socket = SrtSocket(
                    engine: engine,
                    header: udpHeader,
                    events: events,
                    inbox: inbox,
                    send: { [weak self] in self?.send(header: $0, contents: $1) },
                    metrics: metricsService
                )

                confined.sockets[socket.socketId] = SocketRoute(peerSocketId: socket.peerSocketId, inbox: inbox)

                if clearingCaller {
                    confined.pendingCaller = nil
                } else {
                    confined.pendingListener = nil
                }

                handoff = socket
            }
        }

        return handoff
    }
}
