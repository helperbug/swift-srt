import Foundation
@testable import SwiftSrt

/// Test-side view of what a handshake machine asked for.
struct Exchanged {
    let destinationSocketID: UInt32
    let handshake: SrtHandshake
}

extension Array where Element == HandshakeAction {

    var sent: [Exchanged] {
        compactMap { action in
            guard case .send(let packet, let contents) = action,
                  let handshake = SrtHandshake(data: contents) else { return nil }
            return Exchanged(destinationSocketID: packet.destinationSocketID, handshake: handshake)
        }
    }

    var sockets: [SrtSocketContext] {
        compactMap { action in
            guard case .socketCreated(let engine) = action else { return nil }
            return engine
        }
    }
}
