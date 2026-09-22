//
//  SrtCallerInductionRequestingState.swift
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

struct SrtCallerInductionRequestingState: SrtCallerState {
    var name: SrtCallerStates = .inductionRequesting

    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        guard handshake.isInductionResponse else {

            print("Caller: not an induction response (type \(handshake.handshakeType), v\(handshake.hsVersion.rawValue), ext 0x\(String(handshake.extensionField, radix: 16)), cookie \(handshake.synCookie)); giving up")
            context.set(newState: .shutdown)
            return

        }

        guard handshake.hasUsableTransmissionParameters else {

            print("Rejecting induction response with unusable transmission parameters")
            context.set(newState: .shutdown)
            return

        }

        /// Carry the cookie and the listener's socket ID into the conclusion phase.
        context.synCookie = handshake.synCookie
        context.peerSocketID = handshake.srtSocketID

        let state = context.set(newState: .inducted)
        state.auto(context)
        
    }
    
}
