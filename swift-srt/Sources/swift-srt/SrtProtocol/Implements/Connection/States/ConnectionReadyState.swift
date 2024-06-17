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

class ConnectionReadyState: ConnectionState {
    
    let name: ConnectionStates = .ready
    
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
        switch state {
            
        case .failed(let error):
            print("Connection failed with error: \(error)")
            context.set(newState: .failed).state.auto(context)
            
        case .cancelled:
            print("Connection is cancelled.")
            context.set(newState: .cancelled).state.auto(context)
            
        default:
            print("Unexpected change while in ready state: \(state)")
        }
        
    }
    
    func auto(_ context: ConnectionContext) {
        
        context.receiveNextMessage()
        
    }
    
    func send(_ context: ConnectionContext, _ data: Data) {

    }
    
}
