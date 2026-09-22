//
//  ListenerContext.swift
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

import Combine
import Foundation
import Network
import Synchronization

/// Owns one bound UDP port and the connections accepted on it.
public final class SrtPortListenerContext: SrtPortListenerProtocol, Sendable {

    public let endpoint: IPv4Address
    public let port: NWEndpoint.Port
    public let states: AsyncStream<SrtPortListnerStates>
    public let passphrase: String?

    let queue: DispatchQueue
    let logService: LogServiceProtocol
    let managerService: SrtPortManagerServiceProtocol
    let metricsService: SrtMetricsServiceProtocol

    private let stateContinuation: AsyncStream<SrtPortListnerStates>.Continuation

    struct Confined {
        var listener: NWListener?
        var state: SrtPortListenerState = SrtPortListenerNoneState()
    }

    private let confined = Mutex(Confined())

    public static var parameters: NWParameters {
        let srtProtocol = NWProtocolFramer.Options(definition: SrtProtocolFramer.definition)
        let parameters = NWParameters(dtls: nil, udp: NWProtocolUDP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(srtProtocol, at: 0)
        return parameters
    }

    public init(endpoint: IPv4Address,
                port: NWEndpoint.Port,
                passphrase: String? = nil,
                logService: LogServiceProtocol,
                managerService: SrtPortManagerServiceProtocol,
                metricsService: SrtMetricsServiceProtocol) {

        self.endpoint = endpoint
        self.port = port
        self.passphrase = passphrase
        self.queue = DispatchQueue(label: "srt.listener.\(port)", qos: .userInitiated)
        self.logService = logService
        self.managerService = managerService
        self.metricsService = metricsService

        (states, stateContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))

        queue.async { [self] in
            confined.withLock { confined in
                let state = confined.state
                state.auto(&confined, self)
            }
        }
    }

    public var listenerState: SrtPortListnerStates {
        confined.withLock { $0.state.name }
    }

    public func close() {
        confined.withLock { confined in
            confined.listener?.cancel()
            confined.listener = nil
            transition(&confined, to: .none)
        }
    }

    // MARK: Queue callbacks (take the lock)

    func onStateChanged(_ state: NWListener.State) {
        confined.withLock { confined in
            let current = confined.state
            current.onStateChanged(&confined, self, state: state)
        }
    }

    /// Back to the none state and re-arm; used by the error state's retry.
    func restart() {
        confined.withLock { confined in
            transition(&confined, to: .none).auto(&confined, self)
        }
    }

    // MARK: Lock-free

    func accept(_ connection: NWConnection) {

        guard let context = ConnectionContext.make(isHost: true,
                                                   connection,
                                                   passphrase: passphrase,
                                                   logService: logService,
                                                   managerService: managerService,
                                                   metricsService: metricsService) else {
            log("Could not describe accepted connection")
            connection.cancel()
            return
        }

        context.start()

        let manager = managerService
        let header = context.udpHeader
        Task { @MainActor in manager.addConnection(header: header, connection: context) }
    }

    func log(_ message: String) {
        logService.log("⚓️", "Listener", message)
    }

    // MARK: Confined (call only with the lock held)

    @discardableResult
    func transition(_ confined: inout Confined, to state: SrtPortListnerStates) -> SrtPortListenerState {

        let newState: SrtPortListenerState

        switch state {
        case .ready: newState = SrtPortListenerReadyState()
        case .error: newState = SrtPortListenerErrorState()
        case .none: newState = SrtPortListenerNoneState()
        }

        confined.state = newState
        stateContinuation.yield(state)

        /// The error state schedules its own retry back into .none.
        if state == .error {
            newState.auto(&confined, self)
        }

        return newState
    }
}
