//
//  SrtListenerInductionRespondingState.swift
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

struct SrtListenerInductionRespondingState: SrtListenerState {
    
    let name: SrtListenerStates = .inductionResponding
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {

        /// A repeated induction request means our response was lost in flight.
        if handshake.isInductionRequest {

            context.set(newState: .induced).auto(context)
            return

        }

        guard handshake.isConclusionRequest(synCookie: context.synCookie) else {

            /// A mismatched cookie is a forged or stale packet. Drop it and stay
            /// put; tearing the listener down here would let any peer cancel a
            /// handshake in progress.
            print("Ignoring conclusion request with an unrecognised cookie")
            return

        }

        guard handshake.hasUsableTransmissionParameters else {

            print("Ignoring conclusion request with unusable transmission parameters")
            return

        }

        context.apply(handshake: handshake)
        context.set(newState: .inducted).auto(context)
        
    }
    
}
