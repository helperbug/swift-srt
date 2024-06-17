//
//  CipherFamilyAndSizeTypes.swift
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

enum CipherFamilyAndSizeTypes: Int {
    case noEncryptionAdvertised = 0
    case aes128 = 2
    case aes192 = 3
    case aes256 = 4

    var label: String {
        switch self {
        case .noEncryptionAdvertised:
            return "No Encryption Advertised"
        case .aes128:
            return "AES-128"
        case .aes192:
            return "AES-192"
        case .aes256:
            return "AES-256"
        }
    }
}
