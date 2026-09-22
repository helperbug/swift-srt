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
