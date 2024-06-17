//
//  SrtSocketHints.swift
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

/// Represents the hints associated with an SRT socket.
public enum SrtSocketHints {
    
    /// How many frames at 4k60fps using h.265 encoder.
    case hd4k265f60
    
    /// Recommended audio bitrate for high-fidelity streaming.
    case highFidelityAudio
    
    /// Maximum supported resolution for screen sharing based on current network conditions.
    case maxSupportedResolution
    
    /// Optimal settings for video conferencing, balancing quality and latency.
    case videoConferencing
    
}
