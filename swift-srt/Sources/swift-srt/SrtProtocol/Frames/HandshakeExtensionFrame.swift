//
//  HandshakeExtensionFrame.swift
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

/// In a Handshake Extension, the value of the Extension Field of the handshake control packet is defined as 1 for a Handshake Extension request (SRT_CMD_HSREQ in Table 5), and 2 for a Handshake Extension response (SRT_CMD_HSRSP in Table 5).
public struct HandshakeExtensionMessage: ByteFrame {

    public let data: Data

    /// SRT library version MUST be formed as major * 0x10000 + minor * 0x100 + patch.
    public var srtVersion: UInt32 {
        return data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// SRT configuration flags (see Section 3.2.1.1.1).
    public var srtFlags: UInt32 {
        return data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }

    /// Timestamp-Based Packet Delivery (TSBPD) Delay of the receiver, in milliseconds. Refer to Section 4.5.
    public var receiverTsbpdDelay: UInt16 {
        return data.subdata(in: 8..<10).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    /// TSBPD of the sender, in milliseconds. Refer to Section 4.5.
    public var senderTsbpdDelay: UInt16 {
        return data.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }

    public func echo() {
        print("srtVersion: \(srtVersion)")
        print("srtFlags: \(srtFlags)")
        print("receiverTsbpdDelay: \(receiverTsbpdDelay)")
        print("senderTsbpdDelay: \(senderTsbpdDelay)")
    }
    
    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        
        guard bytes.count >= 12 else { return nil }

        self.data = bytes

        echo()
    }

    /// Constructor used when sending over the network
    public init(srtVersion: UInt32, srtFlags: UInt32, receiverTsbpdDelay: UInt16, senderTsbpdDelay: UInt16) {
        var data = Data(capacity: 12)

        var srtVersionBigEndian = srtVersion.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &srtVersionBigEndian) { Data($0) })

        var srtFlagsBigEndian = srtFlags.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &srtFlagsBigEndian) { Data($0) })

        var receiverTsbpdDelayBigEndian = receiverTsbpdDelay.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &receiverTsbpdDelayBigEndian) { Data($0) })

        var senderTsbpdDelayBigEndian = senderTsbpdDelay.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &senderTsbpdDelayBigEndian) { Data($0) })

        self.data = data
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }
    
}
