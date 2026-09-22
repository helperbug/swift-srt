//
//  srt-netem
//
//  Sits between an SRT caller and listener and impairs the link on purpose.
//
//  Usage: srt-netem [--listen 9101] [--to 127.0.0.1:9100] [--loss 0.05]
//                   [--reorder 0.01] [--seed 42] [--seconds 60]
//

import Foundation
import SrtNetem

setvbuf(stdout, nil, _IOLBF, 0)

var listenPort: UInt16 = 9101
var targetHost = "127.0.0.1"
var targetPort: UInt16 = 9100
var profile = ImpairmentProfile(loss: 0.05, reorder: 0)
var seed: UInt64 = 42
var seconds = 60.0

let arguments = Array(CommandLine.arguments.dropFirst())
for (index, argument) in arguments.enumerated() {
    let next = index + 1 < arguments.count ? arguments[index + 1] : nil
    switch argument {
    case "--listen":  if let next, let v = UInt16(next) { listenPort = v }
    case "--to":
        if let next {
            let parts = next.split(separator: ":")
            if parts.count == 2, let port = UInt16(parts[1]) {
                targetHost = String(parts[0]); targetPort = port
            }
        }
    case "--loss":    if let next, let v = Double(next) { profile.loss = v }
    case "--reorder": if let next, let v = Double(next) { profile.reorder = v }
    case "--seed":    if let next, let v = UInt64(next) { seed = v }
    case "--seconds": if let next, let v = Double(next) { seconds = v }
    default: break
    }
}

let proxy = UdpProxy(listenPort: listenPort, targetHost: targetHost, targetPort: targetPort, profile: profile, seed: seed)

do {
    try proxy.start()
} catch {
    print("could not listen on \(listenPort): \(error)")
    exit(1)
}

print(String(format: "srt-netem  udp://:%d → %@:%d   loss %.1f%%  reorder %.1f%%  seed %llu",
             Int(listenPort), targetHost, Int(targetPort), profile.loss * 100, profile.reorder * 100, seed))

func report(_ label: String) {
    let stats = proxy.snapshot
    for direction in UdpProxy.Direction.allCases {
        let c = stats[direction]
        let total = c.forwarded + c.dropped
        let rate = total > 0 ? Double(c.dropped) / Double(total) * 100 : 0
        print(String(format: "%@ %-11@ forwarded %6d  dropped %5d (%.2f%%)  reordered %4d  bytes %d",
                     label, direction == .toTarget ? "→ target" : "← target", c.forwarded, c.dropped, rate, c.reordered, c.bytes))
    }
}

let deadline = Date().addingTimeInterval(seconds)
var nextReport = Date().addingTimeInterval(5)
while Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    if Date() >= nextReport {
        report("  ")
        nextReport = Date().addingTimeInterval(5)
    }
}

proxy.stop()
print("── final ──")
report("  ")
