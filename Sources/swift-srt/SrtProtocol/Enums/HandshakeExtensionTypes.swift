//
//  HandshakeExtensionTypes.swift
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

public enum HandshakeExtensionTypes: UInt16 {
    case none
    case handshakeRequest = 1
    case handshakeResponse = 2
    case keyMaterialRequest = 3
    case keyMaterialResponse = 4
    case streamId = 5
    case congestionControl = 6
    case filterControl = 7
    case groupControl = 8

    var label: String {
        switch self {
        case .none:
            return "None"
        case .handshakeRequest:
            return "Handshake Request"
        case .handshakeResponse:
            return "Handshake Response"
        case .keyMaterialRequest:
            return "Key Material Request"
        case .keyMaterialResponse:
            return "Key Material Response"
        case .streamId:
            return "Stream ID"
        case .congestionControl:
            return "Congestion Control"
        case .filterControl:
            return "Filter Control"
        case .groupControl:	
            return "Group Control"
        }
    }

    var abbreviation: String {
        switch self {
        case .none:
            return "NONE"
        case .handshakeRequest:
            return "SRT_CMD_HSREQ"
        case .handshakeResponse:
            return "SRT_CMD_HSRSP"
        case .keyMaterialRequest:
            return "SRT_CMD_KMREQ"
        case .keyMaterialResponse:
            return "SRT_CMD_KMRSP"
        case .streamId:
            return "SRT_CMD_SID"
        case .congestionControl:
            return "SRT_CMD_CONGESTION"
        case .filterControl:
            return "SRT_CMD_FILTER"
        case .groupControl:
            return "SRT_CMD_GROUP"
        }
    }
}
