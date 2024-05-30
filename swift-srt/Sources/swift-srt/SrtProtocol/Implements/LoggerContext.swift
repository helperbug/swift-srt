//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 5/29/24.
//

import Combine
import Foundation

public class LoggerContext: ObservableObject, LoggerProtocol {
    public var logs: CurrentValueSubject<[String], Never> = .init([])
    
    public init() {
        
    }
    
    public func log(text: String) {
        
    }
    
    public func onConnectionMetric(_ metric: SrtConnectionMetrics) {
        
    }
    
    public func onSocketMetric(_ metric: SrtSocketMetrics) {
        
    }

}
