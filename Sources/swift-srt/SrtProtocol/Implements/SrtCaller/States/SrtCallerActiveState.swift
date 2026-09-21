//
//  SrtCallerActiveState.swift
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

struct SrtCallerActiveState: SrtCallerState {
    var name: SrtCallerStates = .active

    func auto(_ context: SrtCallerContext) {

        /// The listener has answered, so the connection is established. The socket is
        /// keyed by this caller's own ID, which is the destination the listener puts
        /// on the packets it sends back.
        let socket = SrtSocketContext(
            encrypted: context.encrypted,
            socketId: context.srtSocketID,
            synCookie: context.synCookie
        )

        socket.initialPacketSequenceNumber = context.initialPacketSequenceNumber

        /// Carry across what the listener agreed to in its conclusion response.
        socket.srtVersion = context.srtVersion
        socket.srtFlags = context.srtFlags
        socket.receiverTsbpdDelay = context.receiverTsbpdDelay
        socket.senderTsbpdDelay = context.senderTsbpdDelay
        socket.streamId = context.streamId

        context.onSocketCreated(socket)

    }

    /// A repeated conclusion response means our answer was lost; it is safely ignored
    /// because the connection is already up.
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) { }

}
