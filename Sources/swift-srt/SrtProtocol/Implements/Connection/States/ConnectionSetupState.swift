//
//  ConnectionSetupState.swift
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
import Network

struct ConnectionSetupState: ConnectionState {

    let name: ConnectionStates = .setup

    func onStateChanged(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext, state: NWConnection.State) -> SrtSocket? {

        switch state {
        case .preparing:
            /// Already started; calling start() again on a live NWConnection traps.
            context.log("Connection preparing")
            return nil

        case .ready:
            return confined.set(.ready).auto(&confined, context)

        case .failed(let error):
            context.log("Connection failed during setup: \(error)")
            return confined.set(.failed).auto(&confined, context)

        case .cancelled:
            return confined.set(.cancelled).auto(&confined, context)

        default:
            return nil
        }
    }

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? {
        context.connection.start(queue: context.queue)
        return nil
    }
}
