//
//  ControlTypes
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

public enum ControlTypes: UInt16 {
    case handshake = 0x0000
    case keepAlive = 0x0001
    case acknowledgement = 0x0002
    case negativeAcknowledgement = 0x0003
    case congestionWarning = 0x0004
    case shutdown = 0x0005
    case ackack = 0x0006
    case dropRequest = 0x0007
    case peerError = 0x0008
    case userDefined = 0x7FFF
    case none = 0xFFFF
    
    var asField: UInt32 {
        return UInt32(self.rawValue) << 16
    }
}

