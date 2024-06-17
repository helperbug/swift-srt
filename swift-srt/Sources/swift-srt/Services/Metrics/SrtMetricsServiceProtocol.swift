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

public protocol SrtMetricsServiceProtocol: ServiceProtocol {
    
    var uptime: AnyPublisher<Int, Never> { get }
    var listenerMetrics: AnyPublisher<(port: NWEndpoint.Port, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var connectionMetrics: AnyPublisher<(header: UdpHeader, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var socketMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }
    var frameMetrics: AnyPublisher<(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel, send: SrtMetricsModel), Never> { get }

    func storeConnectionMetric(header: UdpHeader, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void
    func storeSocketMetric(header: UdpHeader, socketId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void
    func storeFrameMetric(header: UdpHeader, socketId: UInt32, frameId: UInt32, receive: SrtMetricsModel?, send: SrtMetricsModel?) -> Void

}
