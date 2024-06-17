//
//  KeyMaterialExtensionMessageFrame.swift
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

/// If an encrypted connection is being established, the Key Material (KM) is first transmitted as a Handshake Extension message. This extension is not supplied for unprotected connections. The purpose of the extension is to let peers exchange and negotiate encryption-related information to be used to encrypt and decrypt the payload of the stream.
///
/// The extension can be supplied with the Handshake Extension Type field set to either SRT_CMD_KMREQ or SRT_CMD_KMRSP (see Table 5 in Section 3.2.1). For more details refer to Section 4.3.
///
/// The KM message is placed in the Extension Contents. See Section 3.2.2 for the structure of the KM message.
///
/// In case of SRT_CMD_KMRSP the Extension Length value can be equal to 1 (meaning 4 bytes). It is an indication of encryption failure. In this case the Extension Content has a different format, Figure 7.


public struct KeyMaterialExtensionMessageFrame: ByteFrame {
    
    
    public let data: Data
    
    /// KM State: 32 bits.
    public var kmState: UInt32 {
        
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        
    }
    
    /// Constructor used by the receive network path
    public init?(_ bytes: Data) {
        
        guard bytes.count == 4 else { return nil }
        
        self.data = bytes
        
    }
    
    /// Constructor used when sending over the network
    public init(kmState: UInt32) {
        
        var data = Data(capacity: 4)
        
        var kmStateBigEndian = kmState.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &kmStateBigEndian) { Data($0) })
        
        self.data = data
        
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket { .blank }
    
}
