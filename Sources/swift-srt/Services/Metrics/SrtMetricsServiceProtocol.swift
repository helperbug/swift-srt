//
//  SrtMetricsServiceProtocol.swift
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

public struct ListenerMetrics: Sendable {
    public let port: NWEndpoint.Port
    public let receive: SrtMetricsModel
    public let send: SrtMetricsModel
}

public struct ConnectionMetrics: Sendable {
    public let header: UdpHeader
    public let receive: SrtMetricsModel
    public let send: SrtMetricsModel
}

public struct SocketMetrics: Sendable {
    public let header: UdpHeader
    public let socketId: UInt32
    public let receive: SrtMetricsModel
    public let send: SrtMetricsModel
}

public protocol SrtMetricsServiceProtocol: ServiceProtocol {

    var listenerMetrics: AsyncStream<ListenerMetrics> { get }
    var connectionMetrics: AsyncStream<ConnectionMetrics> { get }
    var socketMetrics: AsyncStream<SocketMetrics> { get }

    /// Hot path: called per packet from inside the connection actor, so these
    /// must be cheap and must not hop isolation.
    func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?)
    func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?)

}
