//
//  LogServiceProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/11/24.
//

import Combine
import Foundation

public class LogService: LogServiceProtocol {
    
    public let icon: String = "🪵"
    public let source: String = "Log"

    @Published private var _logs: (icon: String, source: String, message: String)
    public var logs: AnyPublisher<(icon: String, source: String, message: String), Never> {

        $_logs.eraseToAnyPublisher()

    }
    
    public init() {

        _logs = (icon: "", source: "", message: "")

    }
    
    public func log(_ icon: String, _ source: String, _ message: String) {

        _logs = (icon: icon, source: source, message: message)

    }
    
    public func log(_ message: String) {

        log(self.icon, self.source, message)

    }
    
}
