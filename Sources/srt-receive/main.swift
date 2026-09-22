//
//  srt-receive
//
//  Listens for an SRT caller and writes the received payload out, either to a
//  file or relayed as plain UDP so a player can pick it up live.
//
//  Usage:
//    srt-receive [--port 9000] [--out capture.ts] [--relay 127.0.0.1:1234]
//

import Foundation
import Network
import SwiftSrt

// MARK: Arguments

struct Options {
    var port: UInt16 = 9000
    var outputPath: String?
    var relayHost: String?
    var relayPort: UInt16?
    var seconds: Double = 30
    var passphrase: String?
    var rendezvousHost: String?
    var rendezvousPort: UInt16?

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let next: String? = index + 1 < arguments.count ? arguments[index + 1] : nil

            switch argument {
            case "--port":
                if let next, let value = UInt16(next) { options.port = value }
                index += 1
            case "--out":
                options.outputPath = next
                index += 1
            case "--relay":
                if let next {
                    let parts = next.split(separator: ":")
                    if parts.count == 2, let value = UInt16(parts[1]) {
                        options.relayHost = String(parts[0])
                        options.relayPort = value
                    }
                }
                index += 1
            case "--seconds":
                if let next, let value = Double(next) { options.seconds = value }
                index += 1
            case "--passphrase":
                options.passphrase = next
                index += 1
            case "--rendezvous":
                if let next {
                    let parts = next.split(separator: ":")
                    if parts.count == 2, let value = UInt16(parts[1]) { options.rendezvousHost = String(parts[0]); options.rendezvousPort = value }
                }
                index += 1
            default:
                break
            }

            index += 1
        }

        return options
    }
}

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

// MARK: Output sinks

/// Writes every payload to a file so it can be opened in a player afterwards.
final class FileSink {
    private let handle: FileHandle
    private(set) var bytesWritten = 0

    init?(path: String) {
        let url = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        guard let handle = try? FileHandle(forWritingTo: url) else {
            return nil
        }

        self.handle = handle
    }

    func write(_ data: Data) {
        handle.write(data)
        bytesWritten += data.count
    }

    func close() {
        try? handle.close()
    }
}

/// Relays every payload onward as plain UDP, which any player can open live.
final class UdpRelay {
    private let connection: NWConnection
    private(set) var packetsSent = 0

    init(host: String, port: UInt16) {
        connection = NWConnection(
            host: .init(host),
            port: .init(integerLiteral: port),
            using: .udp
        )
        connection.start(queue: .global(qos: .userInitiated))
    }

    func send(_ data: Data) {
        connection.send(content: data, completion: .idempotent)
        packetsSent += 1
    }

    func close() {
        connection.cancel()
    }
}

let fileSink = options.outputPath.flatMap { FileSink(path: $0) }
let relay: UdpRelay? = {
    guard let host = options.relayHost, let port = options.relayPort else { return nil }
    return UdpRelay(host: host, port: port)
}()

// MARK: Listener

let logService = LogService()
let metricsService = SrtMetricsService(logService: logService, interval: 5)
let manager = SrtPortManagerService(logService: logService, metricsService: metricsService)

var totalBytes = 0
var frameCount = 0
var firstFrameAt: Date?

/// Each accepted socket gets its own task. That task pulls raw packets and
/// runs the engine; the library spawns nothing. Taking the socket as `sending`
/// is what lets a main-actor loop hand it to a detached task.
/// Top-level functions in main.swift are implicitly main-actor; this one must not
/// be, or `sending` the socket into it is not a transfer out of the region.
nonisolated func consume(_ socket: sending SrtSocket) {
    Task.detached(priority: .userInitiated) {
        var lastReport = ContinuousClock.now

        for await event in socket.events {

            for frame in socket.process(event) {
                let payload = frame.payload
                guard !payload.isEmpty else { continue }

                await MainActor.run {
                    if firstFrameAt == nil {
                        firstFrameAt = Date()
                        print("▶︎ first payload from socket \(frame.socketId), \(payload.count) bytes")
                        /// MPEG-TS packets are 188 bytes and start with 0x47. Report what we
                        /// see rather than assuming, so a mismatch is obvious immediately.
                        if let first = payload.first {
                            let looksLikeTs = first == 0x47 && payload.count % 188 == 0
                            print("  first byte 0x\(String(first, radix: 16)), \(payload.count % 188 == 0 ? "" : "not ")a multiple of 188 — \(looksLikeTs ? "looks like MPEG-TS" : "NOT MPEG-TS shaped")")
                        }
                    }

                    totalBytes += payload.count
                    frameCount += 1

                    fileSink?.write(payload)
                    relay?.send(payload)
                }
            }

            if ContinuousClock.now - lastReport > .seconds(5) {
                lastReport = ContinuousClock.now
                report(socket)
            }
        }
        report(socket, final: true)
    }
}

nonisolated func report(_ socket: SrtSocket, final: Bool = false) {
    let s = socket.statistics
    print(String(format: "%@ socket %u  recv %d  lost %d  retrans %d  dropped %d  belated %d  dup %d  delivered %d  acks %d/%d  naks %d  ackacks %d  rtt %.1fms  latency %dms  ticks %d (%d idle)  drift %dµs/%d  decrypted %d  undecryptable %d  km in %d  km rejected %d",
                 final ? "──" : "  ", socket.socketId, s.buffer.received, s.buffer.lost, s.buffer.retransmitted, s.buffer.dropped, s.buffer.belated, s.buffer.duplicates, s.buffer.delivered,
                 s.acksSent, s.lightAcksSent, s.naksSent, s.ackAcksReceived, Double(s.rttMicroseconds) / 1000, Int(s.latencyMicroseconds / 1000), s.ticks, s.ticksWithNothingToAck, Int(s.driftMicroseconds), s.driftCorrections, s.decryptedPackets, s.undecryptablePackets, s.keyMaterialReceived, s.keyMaterialRejected))
}

manager.onSocket { socket in
    print("⇄ socket \(socket.socketId) accepted, streamId \(socket.streamId ?? "-")")
    consume(socket)
}


guard let endpoint = IPv4Address("0.0.0.0"), let port = NWEndpoint.Port(rawValue: options.port) else {
    print("Invalid listen address")
    exit(1)
}

print("Listening for SRT on port \(options.port) for \(Int(options.seconds))s")
if let path = options.outputPath { print("  writing payload to \(path)") }
if let host = options.relayHost, let relayPort = options.relayPort {
    print("  relaying payload to udp://\(host):\(relayPort)")
}

if let host = options.rendezvousHost, let remote = options.rendezvousPort, let address = IPv4Address(host) {
    print("  rendezvous with \(host):\(remote) from local port \(options.port)")
    manager.rendezvous(with: address, port: NWEndpoint.Port(integerLiteral: remote), localPort: port, streamId: nil, passphrase: options.passphrase)
} else {
    manager.addListener(endpoint: endpoint, port: port, passphrase: options.passphrase)
}

// MARK: Run

let deadline = Date().addingTimeInterval(options.seconds)
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
}

fileSink?.close()
relay?.close()

print()
print("── summary ──")
print("connections    : \(manager.connections.count)")
print("payload frames : \(frameCount)")
print("payload bytes  : \(totalBytes)")
if let fileSink { print("written to file: \(fileSink.bytesWritten) bytes") }
if let relay { print("relayed packets: \(relay.packetsSent)") }

if frameCount == 0 {
    print("No payload received.")
    exit(2)
}
