//
//  SrtSocketProtocol.swift
//
//
//  Created by Ben Waidhofer on 5/26/24.
//

import Combine
import Foundation

/// The SrtSocketProtocol abstracts the details of breaking up frames into data packets, generating metrics, and handling retransmissions. It defines the core properties and methods necessary for interacting with SRT sockets, ensuring consistency and compatibility within the SRT framework.
public protocol SrtSocketProtocol {
    
    /// Whether the socket uses encryption.
    var encrypted: Bool { get }
    
    /// The socket ID used when sending data packets.
    var id: UInt32 { get }
    
    /// Each full video, audio or still frame is delivered here.
    var onFrameReceived: (Data) -> Void { get }
    
    /// Hints are reported once each second along with the metrics
    var onHintsReceived: ([SrtSocketHints]) -> Void { get }
    
    /// Metrics are available at the same time as KeepAlive.
    var onMetricsReceived: ([SrtSocketMetrics]) -> Void { get }
    
    /// Each socket state transition is reported here.
    var onStateChanged: (SrtSocketStates) -> Void { get }
    
    /// Sends the specified data through the SRT socket. The frame will be decomposed into packets and tracked using ACKs and NACKs.
    ///
    /// - Parameter data: The data to be sent.
    func sendFrame(data: Data) -> Void
    
}
