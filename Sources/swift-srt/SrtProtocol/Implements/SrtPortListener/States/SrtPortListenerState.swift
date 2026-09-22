//
//  ListenerState.swift
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

// MARK: Listener State Protocol

/// States run with the listener's lock held and mutate its confined state
/// through the inout parameter.
protocol SrtPortListenerState {

    var name: SrtPortListnerStates { get }

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State)
    func auto(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext)

}

// MARK: Defaults

extension SrtPortListenerState {

    func onStateChanged(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext, state: NWListener.State) {
        context.log("Ignoring \(state) in listener state \(name.label)")
    }

    func auto(_ confined: inout SrtPortListenerContext.Confined, _ context: SrtPortListenerContext) { }

}
