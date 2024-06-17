//
//  SrtSocketMetrics.swift
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

/// Represents the metrics associated with an SRT socket.
public enum SrtSocketMetrics {
    
    /// Bandwidth usage in Mbps over the last second
    case bandwidth(Double)
    
    /// Packet loss rate as a percentage over the last second
    case packetLossRate(Double)
    
    /// Round-trip time (RTT) in milliseconds over the last second
    case roundTripTime(Double)
    
    /// Jitter in milliseconds average over the last second
    case jitter(Double)
    
    /// Latency in milliseconds average over the last second
    case latency(Double)
    
    /// Total number of ACKs received
    case ackCount(Int)
    
    /// Total number of expired data packets that needed retransmission
    case retransmissionCount(Int)
    
    /// Keep-alive messages sent once per second on the second
    case keepAliveMessages(Int)
    
    /// Current state of the socket
    case socketState(SrtSocketStates)
    
}
