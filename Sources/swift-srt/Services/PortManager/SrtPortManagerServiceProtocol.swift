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

public protocol SrtPortManagerServiceProtocol: ServiceProtocol {
    
    var listeners: AnyPublisher<[NWEndpoint.Port: SrtPortListenerProtocol], Never> { get }
    var connections: AnyPublisher<[UdpHeader: SrtConnectionProtocol], Never> { get }
    var metrics: AnyPublisher<(UdpHeader, SrtMetricsModel), Never> { get }
    var sockets: AnyPublisher<[UdpHeader: [UInt32: SrtSocketProtocol]], Never> { get }
    var frames: AnyPublisher<(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data), Never> { get }

    func addListener(endpoint: IPv4Address, port: NWEndpoint.Port) -> Void
    func addConnection(header: UdpHeader, connection: SrtConnectionProtocol) -> Void
    func addSocket(header: UdpHeader, socket: SrtSocketProtocol) -> Void
    func addFrame(header: UdpHeader, socketId: UInt32, messageId: UInt32, frame: Data) -> Void
    
    func removeListener(port: NWEndpoint.Port) -> Void
    func removeConnection(header: UdpHeader) -> Void
    func removeSocket(header: UdpHeader, socketId: UInt32) -> Void

    func shutdown(port: NWEndpoint.Port?) -> Void
    func shutdownConnection(connection: UdpHeader) -> Void
    
}
