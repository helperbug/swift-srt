//
//  ListenerState.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/1/2024.
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

protocol SrtPortListenerState {
    
    var name: SrtPortListnerStates { get }
    
    func onStateChanged(_ context: SrtPortListenerContext, state: NWListener.State) -> Void
    func primary(_ context: SrtPortListenerContext) -> Void
    func auto(_ context: SrtPortListenerContext) -> Void
    func fail(_ context: SrtPortListenerContext) -> Void
    
}

// MARK: Defaults

extension SrtPortListenerState {
    
    func primary(_ context: SrtPortListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: SrtPortListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: SrtPortListenerContext) {
        
        fatalError(name.label)
        
    }
    
}

