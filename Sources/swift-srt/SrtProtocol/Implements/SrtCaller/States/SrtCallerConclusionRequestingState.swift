//
//  SrtCallerConclusionRequestingState.swift
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

struct SrtCallerConclusionRequestingState: SrtCallerState {
    var name: SrtCallerStates = .conclusionRequesting

    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        /// The listener replies with a conclusion response carrying HSRSP -- not with
        /// another conclusion request.
        guard handshake.isConclusionResponse else {

            print("Caller: not a conclusion response (type \(handshake.handshakeType), ext 0x\(String(handshake.extensionField, radix: 16)), exts \(handshake.extensions.keys.map(\.label))); giving up")
            context.set(newState: .shutdown)
            return

        }

        guard handshake.hasUsableTransmissionParameters else {

            print("Rejecting conclusion response with unusable transmission parameters")
            context.set(newState: .shutdown)
            return

        }

        context.apply(handshake: handshake)

        /// Our key material must come back verbatim; four bytes is a refusal.
        if let encryption = context.encryption {
            guard let response = handshake.keyMaterialResponse else {
                print("Caller: peer answered without key material; refusing to run in the clear")
                context.fail(encryption: .peerRejected(.unsecured))
                context.set(newState: .shutdown)
                return
            }
            if case .failure(let error) = encryption.accept(keyMaterialResponse: response) {
                print("Caller: key exchange failed: \(error)")
                context.fail(encryption: error)
                context.set(newState: .shutdown)
                return
            }
        }

        /// The peer's socket only exists once it accepts, so this response is
        /// the first packet that can carry its real ID. libsrt's induction
        /// response echoes the caller's own ID there, so trusting that would
        /// address every reply to ourselves.
        context.peerSocketID = handshake.srtSocketID

        let state = context.set(newState: .active)
        state.auto(context)
        
    }
}
