//
//  SrtConnectionProtocol.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 5/25/2024.
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

public protocol SrtConnectionProtocol {

    var udpHeader: UdpHeader { get }
    var onCanceled: (UdpHeader) -> Void { get }
    var sockets: [UInt32: SrtSocketProtocol] { get }
    var connectionState: ConnectionStates { get }
    var receiveMetrics: AnyPublisher<SrtMetricsModel, Never> { get }
    var sendMetrics: AnyPublisher<SrtMetricsModel, Never> { get }
    var uptime: AnyPublisher<TimeInterval, Never> { get }

    init(updHeader: UdpHeader,
         connection: NWConnection,
         managerService: SrtPortManagerServiceProtocol,
         metricsService: SrtMetricsServiceProtocol,
         onCanceled: @escaping (UdpHeader) -> Void,
         onDataPacket: @escaping (DataPacketFrame) -> Void)

    func cancel() -> Void
    func removeSocket(id: UInt32) -> Void
    
}
