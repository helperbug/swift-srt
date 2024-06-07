//
//  SrtListenerState.swift
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

protocol SrtListenerState {
    
    var name: SrtListenerStates { get }
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) -> Void
    func primary(_ context: SrtListenerContext) -> Void
    func auto(_ context: SrtListenerContext) -> Void
    func fail(_ context: SrtListenerContext) -> Void
    
}

// MARK: Defaults

extension SrtListenerState {
    
    func primary(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: SrtListenerContext) {
        
        fatalError(name.label)
        
    }
    
    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {
        
        fatalError(name.label)
        
    }
    
}
