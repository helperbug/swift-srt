//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/15/24.
//

import Foundation

struct SrtCallerActiveState: SrtCallerState {
    var name: SrtCallerStates = .active

    func handleHandshake(_ context: SrtListenerContext, handshake: SrtHandshake) {

        print("handshake caller active")
        
    }

}
