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

import Combine
import Foundation

public final class LogService: LogServiceProtocol {

    public let icon = "🪵"
    public let source = "Log"

    public let entries: AsyncStream<LogEntry>
    private let continuation: AsyncStream<LogEntry>.Continuation

    public init() {
        (entries, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    /// Safe to call from any isolation: it prints and yields to the stream,
    /// both of which are thread-safe.
    public func log(_ icon: String, _ source: String, _ message: String) {
        print("\(icon) \(source): \(message)")
        continuation.yield(LogEntry(icon: icon, source: source, message: message))
    }

    public func log(_ message: String) {
        log(icon, source, message)
    }

}
