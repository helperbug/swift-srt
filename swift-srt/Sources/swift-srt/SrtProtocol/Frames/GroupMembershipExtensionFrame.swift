//
//  GroupMembershipExtensionFrame.swift
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

/// The Group Membership handshake extension is reserved for the future and is going to be used to allow multipath SRT connections.
public struct GroupMembershipExtensionFrame: ByteFrame {
    
    public let data: Data
    
    /// The identifier of a group whose members include the sender socket that is making a connection. The target socket that is interpreting GroupID SHOULD belong to the corresponding group on the target side. If such a group does not exist, the target socket MAY create it.
    public var groupId: UInt32 {
        data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
    }
    
    /// Group type, as per SRT_GTYPE_ enumeration:
    /// 0: undefined group type,
    /// 1: broadcast group type,
    /// 2: main/backup group type,
    /// 3: balancing group type,
    /// 4: multicast group type (reserved for future use).
    public var type: UInt8 {
        data[4]
    }
    
    /// Special flags mostly reserved for the future. See Figure 10.
    public var flags: UInt8 {
        data[5]
    }
    
    /// Special value with interpretation depending on the Type field value:
    /// Not used with broadcast group type,
    /// Defines the link priority for main/backup group type,
    /// Not yet defined for any other cases (reserved for future use).
    /// M (1 bit) When set, defines synchronization on message numbers, otherwise transmission is synchronized on sequence numbers.
    /*
     0 1 2 3 4 5 6 7
     +-+-+-+-+-+-+-+
     |   (zero)  |M|
     +-+-+-+-+-+-+-+
     */
    public var weight: UInt16 {
        data.subdata(in: 6..<8).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
    }
    
    /// Indicates if the synchronization is on message numbers based on the Group Membership Extension Flags.
    var useMessageNumber: Bool {
        return flags & 0b00000001 != 0
    }
    
    /// Constructor from individual fields for Group Membership information.
    public init(groupID: UInt32, type: UInt8, flags: UInt8, weight: UInt16) {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: groupID.bigEndian, Array.init))
        data.append(contentsOf: [type, flags])
        data.append(contentsOf: withUnsafeBytes(of: weight.bigEndian, Array.init))
        self.data = data
    }
    
    /// Optional initializer from Data, validating the minimum required length.
    public init?(_ data: Data) {
        
        guard data.count == 8 else { return nil }
        
        self.data = data
        
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }
    
}
