//
//  ConnectionSetupState.swift
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

class ConnectionSetupState: ConnectionState {
    
    let name: ConnectionStates = .setup
    
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        
        if state == .preparing {
            
            let state = context.set(newState: .setup)
            state.state.auto(context)

        } else if state == .ready {
            
            let state = context.set(newState: .ready)
            state.state.auto(context)

        }
        
        if let queue = context.connection.queue {
            context.connection.requestEstablishmentReport(queue: queue) { report in
                guard let report else {
                    return
                }
                
                let message = String(format: "Duration of establishment: %.0f microseconds", report.duration * 1000000)
                context.log(message)
            }
        }
    }
    
    func auto(_ context: ConnectionContext) {
        
        context.connection.start(queue: .global(qos: .utility))

    }
    
    func fail(_ context: ConnectionContext) {

        context.connection.cancel()

    }
    
}
