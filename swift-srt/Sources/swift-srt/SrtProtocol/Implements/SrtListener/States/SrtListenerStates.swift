//
//  SrtListenerStates
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

enum SrtListenerStates {
    case induced
    case inductionResponding
    case inducted
    case conclusionResponding
    case active
    case shutdown
    case error

    var label: String {
        switch self {
        case .induced:
            return "Induced"
        case .inductionResponding:
            return "Induction Responding"
        case .inducted:
            return "Inducted"
        case .conclusionResponding:
            return "Conclusion Responding"
        case .active:
            return "Active"
        case .shutdown:
            return "Shutdown"
        case .error:
            return "Error"
        }
    }

    var color: String {
        switch self {
        case .induced:
            return "Blue"
        case .inductionResponding:
            return "Orange"
        case .inducted:
            return "Green"
        case .conclusionResponding:
            return "Yellow"
        case .active:
            return "Green"
        case .shutdown:
            return "Red"
        case .error:
            return "Red"
        }
    }

    var symbol: String {
        switch self {
        case .induced:
            return "arrow.right.circle"
        case .inductionResponding:
            return "arrow.triangle.2.circlepath"
        case .inducted:
            return "checkmark.circle"
        case .conclusionResponding:
            return "paperplane.circle"
        case .active:
            return "waveform.circle"
        case .shutdown:
            return "power.circle"
        case .error:
            return "xmark.octagon"
        }
    }
    
    var instance: SrtListenerState {
        switch self {
        case .induced:
            return StrListenerInducedState()
        case .inductionResponding:
            return SrtListenerInductionRespondingState()
        case .inducted:
            return StrListenerInductedState()
        case .conclusionResponding:
            return SrtListenerConclusionRespondingState()
        case .active:
            return SrtListenerActiveState()
        case .shutdown:
            return SrtListenerShutdownState()
        case .error:
            return SrtListenerErrorStateState()
        }
    }
    
}
