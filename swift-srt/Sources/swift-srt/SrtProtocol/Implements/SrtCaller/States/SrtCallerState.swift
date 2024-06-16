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

// MARK: Caller State Protocol

protocol SrtCallerState {
    
    var name: SrtCallerStates { get }
    
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) -> Void
    func primary(_ context: SrtCallerContext) -> Void
    func auto(_ context: SrtCallerContext) -> Void
    func fail(_ context: SrtCallerContext) -> Void
    
}

// MARK: Defaults

extension SrtCallerState {
    
    func primary(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    func auto(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    func fail(_ context: SrtCallerContext) {
        
        fatalError(name.label)
        
    }
    
    func handleHandshake(_ context: SrtCallerContext, handshake: SrtHandshake) {
        
        fatalError(name.label)
        
    }
    
}