//
//  SrtMetricsModel.swift
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

import Foundation

public struct SrtMetricsModel: Identifiable {
    
    public let id: UUID = .init()
    public let ackAckCount: Int
    public let ackCount: Int
    public let bytesCount: Int
    public let controlCount: Int
    public let dataPacketCount: Int
    public let jitter: Double
    public let latency: Double
    public let nackCount: Int
    public let roundTripTime: Double
    
    init(
        ackAckCount: Int = 0,
        ackCount: Int = 0,
        bytesCount: Int = 0,
        controlCount: Int = 0,
        dataPacketCount: Int = 0,
        jitter: Double = 0.0,
        latency: Double = 0.0,
        nackCount: Int = 0,
        roundTripTime: Double = 0.0
    ) {
        self.ackAckCount = ackAckCount
        self.ackCount = ackCount
        self.bytesCount = bytesCount
        self.controlCount = controlCount
        self.dataPacketCount = dataPacketCount
        self.jitter = jitter
        self.latency = latency
        self.nackCount = nackCount
        self.roundTripTime = roundTripTime
    }
    
    public static var blank: SrtMetricsModel {
        .init(
            ackAckCount: 0,
            ackCount: 0,
            bytesCount: 0,
            controlCount: 0,
            dataPacketCount: 0,
            jitter: 0.0,
            latency: 0.0,
            nackCount: 0,
            roundTripTime: 0.0
        )
    }
}
