//
//  srt-player
//
//  A native SRT player: SRT in, decoded video on screen. No VLC, no relay.
//
//  Usage: srt-player [--port 9000] [--delay 150] [--trace file.csv] [--passphrase secret]
//

import AppKit
import SwiftSrtMedia
import SwiftUI

@main
struct SrtPlayerApp: App {

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    @State private var player: SrtPlayer
    private let port: UInt16
    private let passphrase: String?

    init() {
        setvbuf(stdout, nil, _IOLBF, 0)

        var port: UInt16 = 9000
        var delay = 150
        var trace: URL?
        var passphrase: String?

        let arguments = Array(CommandLine.arguments.dropFirst())
        for (index, argument) in arguments.enumerated() {
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch argument {
            case "--port":  if let next, let v = UInt16(next) { port = v }
            case "--delay": if let next, let v = Int(next) { delay = v }
            case "--trace": if let next { trace = URL(fileURLWithPath: next) }
            case "--passphrase": passphrase = next
            default: break
            }
        }

        self.port = port
        self.passphrase = passphrase
        _player = State(initialValue: SrtPlayer(presentationDelayMs: delay, traceURL: trace))
    }

    var body: some Scene {
        WindowGroup("swift-srt player — srt://0.0.0.0:\(String(port))") {
            PlayerView(player: player)
                .frame(minWidth: 640, minHeight: 360)
                .task {
                    player.listen(on: port, passphrase: passphrase)
                    print("srt-player listening on srt://0.0.0.0:\(String(port))")
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                        let transport = player.stats.snapshot
                        print("── \(player.summary)")
                        print("   render  slack ms    \(player.renderer.slackMs.summary)")
                        print("   render  interval ms \(player.renderer.intervalMs.summary)")
                        print("   srt pkt interval ms \(transport.packets.summary)")
                        print("   au      interval ms \(transport.units.summary)")
                    }
                }
        }
        .defaultSize(width: 1280, height: 720)
    }
}

struct PlayerView: View {

    let player: SrtPlayer

    private var overlay: String {
        var line = "\(String(player.renderer.framesPresented)) frames · \(String(player.renderer.framesLate)) late"
        if let stats = player.socketStatistics.values.first {
            line += String(format: " · lost %d · retrans %d · dropped %d · rtt %.1f ms · latency %d ms",
                           stats.buffer.lost, stats.buffer.retransmitted, stats.buffer.dropped,
                           Double(stats.rttMicroseconds) / 1000, Int(stats.latencyMicroseconds / 1000))
        }
        return line
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SrtVideoView(renderer: player.renderer)
                .ignoresSafeArea()

            Text(overlay)
                .font(.system(.caption, design: .monospaced))
                .padding(6)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
                .padding(10)
        }
        .background(.black)
    }
}

/// A bare executable has no bundle, so it does not become a regular app on
/// its own; do that here so the window actually comes to the front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
