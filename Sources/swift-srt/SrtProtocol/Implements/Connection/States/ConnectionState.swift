//
//  ConnectionState.swift
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

// MARK: Protocol

protocol ConnectionState {
    var name: ConnectionStates { get }
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State)
    func primary(_ context: ConnectionContext) -> Void
    func auto(_ context: ConnectionContext) -> Void
    func fail(_ context: ConnectionContext) -> Void
    func send(_ context: ConnectionContext, _ data: Data) -> Void
}

extension ConnectionState {
    
    func primary(_ context: ConnectionContext) {
        fatalError(name.label)
    }

    func auto(_ context: ConnectionContext) {
        fatalError(name.label)
    }

    func fail(_ context: ConnectionContext) {
        fatalError(name.label)
    }
    
    func send(_ context: ConnectionContext, _ data: Data) {
        fatalError(name.label)
    }
    
    func onStateChanged(_ context: ConnectionContext, state: NWConnection.State) {
        fatalError(name.label)
    }
}


// MARK: Waiting State

class ConnectionWaitingState: ConnectionState {

    let name: ConnectionStates = .waiting
    
}

// MARK: Preparing State

class ConnectionPreparingState: ConnectionState {
    let name: ConnectionStates = .preparing
}


// MARK: Failed State

class ConnectionFailedState: ConnectionState {
    let name: ConnectionStates = .failed
    
    func auto(_ context: ConnectionContext) {
        context.cancel()
    }
    
}

// MARK: Cancelled State

class ConnectionCancelledState: ConnectionState {
    let name: ConnectionStates = .cancelled

    func auto(_ context: ConnectionContext) {
        context.cancel()
    }
    
}
