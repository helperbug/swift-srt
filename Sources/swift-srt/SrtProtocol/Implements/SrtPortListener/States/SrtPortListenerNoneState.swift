//
//  ListenerNoneState.swift
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

// MARK: None State

struct SrtPortListenerNoneState: SrtPortListenerState {

    let name: SrtPortListnerStates = .none

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State) {

        switch state {
        case .ready:
            context.transition(&confined, to: .ready)
        case .failed(let error):
            context.log("Listener failed: \(error)")
            context.transition(&confined, to: .error)
        default:
            break
        }
    }

    func auto(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext) {

        do {
            let listener = try NWListener(using: SrtPortListenerContext.parameters, on: context.port)

            /// Both handlers are delivered on `context.queue`.
            listener.newConnectionHandler = { [weak context] connection in
                context?.accept(connection)
            }

            listener.stateUpdateHandler = { [weak context] state in
                context?.onStateChanged(state)
            }

            confined.listener = listener
            listener.start(queue: context.queue)

        } catch {
            context.log("Could not bind port \(context.port): \(error)")
            context.transition(&confined, to: .error)
        }
    }
}
