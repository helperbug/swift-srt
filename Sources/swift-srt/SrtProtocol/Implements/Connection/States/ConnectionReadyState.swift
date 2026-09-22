//
//  ConnectionReadyState.swift
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

struct ConnectionReadyState: ConnectionState {

    let name: ConnectionStates = .ready

    func onStateChanged(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext, state: NWConnection.State) -> SrtSocket? {

        switch state {
        case .failed(let error):
            context.log("Connection failed: \(error)")
            return confined.set(.failed).auto(&confined, context)

        case .cancelled:
            context.log("Connection cancelled")
            return confined.set(.cancelled).auto(&confined, context)

        default:
            context.log("Unexpected change while ready: \(state)")
            return nil
        }
    }

    func auto(_ confined: inout ConnectionContext.Confined, _ context: ConnectionContext) -> SrtSocket? {
        context.receiveNextMessage()
        confined.ticker = context.makeTicker()

        /// A caller or rendezvous asked to start before the socket was up: go now.
        if let request = confined.rendezvousRequest {
            return context.beginRendezvous(address: request.address, streamId: request.streamId, &confined)
        }
        guard let request = confined.callerRequest else { return nil }
        return context.beginCallerHandshake(address: request.address, streamId: request.streamId, &confined)
    }
}
