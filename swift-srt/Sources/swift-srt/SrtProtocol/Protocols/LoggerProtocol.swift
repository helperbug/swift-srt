//
//  LoggerProtocol.swift
//
//
//  Created by Ben Waidhofer on 5/29/24.
//

import Combine
import Foundation

public protocol LoggerProtocol {
    
    var logs: CurrentValueSubject<[String], Never> { get }
    
    func log(text: String) -> Void
    func onConnectionMetric(_ metric: SrtConnectionMetrics) -> Void
    func onSocketMetric(_ metric: SrtSocketMetrics) -> Void

}
