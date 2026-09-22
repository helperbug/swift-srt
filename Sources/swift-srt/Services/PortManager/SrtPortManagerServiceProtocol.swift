//
//  SrtPortManagerProtocol.swift
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

/// One received SRT payload, as delivered to the application.
public struct SrtFrame: Sendable {
    public let header: UdpHeader
    public let socketId: UInt32
    public let messageId: UInt32
    public let payload: Data
}

@MainActor
public protocol SrtPortManagerServiceProtocol: ServiceProtocol {

    var listeners: [NWEndpoint.Port: any SrtPortListenerProtocol] { get }
    var connections: [UdpHeader: any SrtConnectionProtocol] { get }

    /// Registers the subscriber that owns every socket from here on. Called from
    /// the connection's reader thread the instant a handshake completes, with
    /// the socket transferred (`sending`) to it. The subscriber decides what
    /// task pulls the socket's `packets`; the library spawns none.
    nonisolated func onSocket(_ handler: @escaping @Sendable (sending SrtSocket) -> Void)

    func addListener(endpoint: IPv4Address, port: NWEndpoint.Port, passphrase: String?)

    /// Calls an SRT listener. The socket arrives through `onSocket` like any
    /// other once the handshake completes.
    func connect(to address: IPv4Address, port: NWEndpoint.Port, streamId: String?, passphrase: String?)

    /// Meets a peer that is doing the same: both bind a local port and call
    /// each other, which is what gets through a NAT on both ends.
    func rendezvous(with address: IPv4Address, port: NWEndpoint.Port, localPort: NWEndpoint.Port, streamId: String?, passphrase: String?)
    func addConnection(header: UdpHeader, connection: any SrtConnectionProtocol)
    nonisolated func addSocket(_ socket: sending SrtSocket)

    func removeListener(port: NWEndpoint.Port)
    func removeConnection(header: UdpHeader)

    func shutdown(port: NWEndpoint.Port?)
    func shutdownConnection(header: UdpHeader)

}
