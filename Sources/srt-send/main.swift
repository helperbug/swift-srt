//
//  srt-send
//
//  Takes MPEG-TS over plain UDP and sends it over SRT, as a listener waiting
//  for a caller, or as a caller to a listener. The mirror of srt-receive.
//
//  Usage:
//    srt-send --from 1237 --listen 9100            # wait for an SRT caller
//    srt-send --from 1237 --to 127.0.0.1:9200      # call an SRT listener
//

import Foundation
import Network
import SwiftSrt
import Synchronization

setvbuf(stdout, nil, _IOLBF, 0)

var fromPort: UInt16 = 1237
var listenPort: UInt16?
var toHost: String?
var toPort: UInt16?
var seconds = 60.0
var passphrase: String?
var keyRefreshRate: UInt32?
var keyPreAnnounce: UInt32?
var rendezvousHost: String?
var rendezvousPort: UInt16?
var localPort: UInt16 = 9300

let arguments = Array(CommandLine.arguments.dropFirst())
for (index, argument) in arguments.enumerated() {
    let next = index + 1 < arguments.count ? arguments[index + 1] : nil
    switch argument {
    case "--from":    if let next, let v = UInt16(next) { fromPort = v }
    case "--listen":  if let next, let v = UInt16(next) { listenPort = v }
    case "--to":
        if let next {
            let parts = next.split(separator: ":")
            if parts.count == 2, let port = UInt16(parts[1]) { toHost = String(parts[0]); toPort = port }
        }
    case "--seconds": if let next, let v = Double(next) { seconds = v }
    case "--passphrase": passphrase = next
    case "--km-refresh": if let next, let v = UInt32(next) { keyRefreshRate = v }
    case "--km-preannounce": if let next, let v = UInt32(next) { keyPreAnnounce = v }
    case "--local": if let next, let v = UInt16(next) { localPort = v }
    case "--rendezvous":
        if let next {
            let parts = next.split(separator: ":")
            if parts.count == 2, let port = UInt16(parts[1]) { rendezvousHost = String(parts[0]); rendezvousPort = port }
        }
    default: break
    }
}

let logService = LogService()
let metricsService = SrtMetricsService(logService: logService, interval: 5)
let manager = SrtPortManagerService(logService: logService, metricsService: metricsService)

/// Whoever is connected gets the stream. One outbound at a time is enough here.
let outbound = Mutex<SrtSocketOutbound?>(nil)
let counters = Mutex((datagrams: 0, bytes: 0, sent: 0))

nonisolated func own(_ socket: sending SrtSocket) {
    outbound.withLock { $0 = socket.outbound }
    Task.detached(priority: .userInitiated) {
        var lastReport = ContinuousClock.now
        for await event in socket.events {
            _ = socket.process(event)
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
    print(String(format: "%@ socket %u  sent %d  retrans %d  acked %d  dropped %d  acks %d  naks %d  ackacks %d  dropreq %d  keepalives %d  peer rtt %.1fms  peer buf %u  km sent %d  refreshes %d",
                 final ? "──" : "  ", socket.socketId, s.send.sent, s.send.retransmitted, s.send.acknowledged, s.send.dropped,
                 s.acksReceived, s.naksReceived, s.ackAcksSent, s.dropRequestsSent, s.keepAlivesSent,
                 Double(s.peerRttMicroseconds) / 1000, s.peerAvailableBuffer, s.keyMaterialSent, s.keyRefreshes))
}

/// Read from the socket handler, which is not main-actor: a `let` of a
/// Sendable value is fine there where the parsed `var`s are not.
let keyRefresh: (rate: UInt32, preAnnounce: UInt32)? = keyRefreshRate.map { ($0, keyPreAnnounce ?? $0 / 4) }

manager.onSocket { socket in
    print("⇄ socket \(socket.socketId) up, peer \(socket.peerSocketId); streaming")
    if let keyRefresh {
        socket.setKeyRefresh(rate: keyRefresh.rate, preAnnounce: keyRefresh.preAnnounce)
    }
    own(socket)
}

/// Plain UDP in. Each datagram is one SRT message.
let source = try! NWListener(using: .udp, on: NWEndpoint.Port(integerLiteral: fromPort))
let sourceQueue = DispatchQueue(label: "srt-send.source")
source.newConnectionHandler = { connection in
    connection.start(queue: sourceQueue)
    nonisolated func pump(_ connection: NWConnection) {
        connection.receiveMessage { data, _, _, error in
            guard error == nil else { return }
            if let data, !data.isEmpty {
                counters.withLock { $0.datagrams += 1; $0.bytes += data.count }
                if let out = outbound.withLock({ $0 }) {
                    out.send(data)
                    counters.withLock { $0.sent += 1 }
                }
            }
            pump(connection)
        }
    }
    pump(connection)
}
source.start(queue: sourceQueue)

if let rendezvousHost, let rendezvousPort, let address = IPv4Address(rendezvousHost) {
    manager.rendezvous(with: address, port: NWEndpoint.Port(integerLiteral: rendezvousPort), localPort: NWEndpoint.Port(integerLiteral: localPort), streamId: nil, passphrase: passphrase)
    print("srt-send: udp://:\(fromPort) → srt rendezvous with \(rendezvousHost):\(rendezvousPort) from :\(localPort)")
} else if let listenPort {
    manager.addListener(endpoint: IPv4Address("0.0.0.0")!, port: NWEndpoint.Port(integerLiteral: listenPort), passphrase: passphrase)
    print("srt-send: udp://:\(fromPort) → srt listener on :\(listenPort)")
} else if let toHost, let toPort, let address = IPv4Address(toHost) {
    manager.connect(to: address, port: NWEndpoint.Port(integerLiteral: toPort), streamId: nil, passphrase: passphrase)
    print("srt-send: udp://:\(fromPort) → srt caller to \(toHost):\(toPort)")
} else {
    print("need --listen PORT or --to HOST:PORT"); exit(1)
}

let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
let c = counters.withLock { $0 }
print("── source datagrams \(c.datagrams)  bytes \(c.bytes)  forwarded \(c.sent)")
