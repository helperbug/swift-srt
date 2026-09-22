//
//  LogServiceProtocol.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Combine
import Foundation

public struct LogEntry: Sendable {
    public let icon: String
    public let source: String
    public let message: String
}

public protocol LogServiceProtocol: ServiceProtocol {

    /// Every log line, for anything that wants to observe them.
    var entries: AsyncStream<LogEntry> { get }

    func log(_ icon: String, _ source: String, _ message: String)

}
