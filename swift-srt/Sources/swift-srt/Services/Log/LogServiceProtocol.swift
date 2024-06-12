//
//  LogServiceProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/11/24.
//

import Combine
import Foundation

public protocol LogServiceProtocol: ServiceProtocol {
    
    var logs: AnyPublisher<(icon: String, source: String, message: String), Never> { get }

    func log(_ icon: String, _ source: String, _ message: String) -> Void
    
}
