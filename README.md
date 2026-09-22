# swift-srt

Secure Reliable Transport (SRT) in Swift, on Apple's Network framework. Swift 6
language mode with full data-race safety, no `@unchecked Sendable`, no
`nonisolated(unsafe)`. macOS, iOS, tvOS and watchOS 26 and later.

The wire protocol follows the SRT specification and is verified against
libsrt 1.5.7 in both roles. The API is Swift-native: sockets arrive as values
you own, packets come through an `AsyncStream`, and the library spawns no
tasks of its own for the data path.

## Status

Pre-alpha. Handshakes in all three modes, receive, send and encryption are
complete and tested against libsrt 1.5.7.

| | State |
|---|---|
| Caller-listener handshake, both roles | done, interoperates with libsrt 1.5.7 |
| Receive: reorder buffer, ACK, NAK, RTT, TSBPD with drift tracing, too-late drop | done |
| Send: sequencing, retransmission on NAK, DROPREQ, keep-alive, flow window | done |
| Loss testing | byte-exact through 10% loss; through 20% at 1 s latency |
| MPEG-TS demux, H.264 to `CMSampleBuffer`, SwiftUI player | done |
| Encryption: AES-CTR, PBKDF2 key derivation, RFC 3394 key wrap, KMREQ/KMRSP | done, interoperates with libsrt; key refresh not yet |
| Rendezvous handshake | done, interoperates with libsrt |
| Bandwidth pacing | not yet: the application paces, retransmissions are not smoothed |
| Bonding, FEC, file mode | out of scope |

## Design

One thread reads datagrams off the wire and routes each by destination socket
ID into that socket's stream. Whoever subscribes to a socket owns it: their
task pulls events and calls `process`, which runs the protocol -- ACKs, NAKs,
retransmissions, keep-alives -- and hands back payload. Fan-out across
cameras is the application's choice of tasks, not the library's.

```swift
let manager = SrtPortManagerService(logService: LogService(), metricsService: metrics)

manager.onSocket { socket in
    Task.detached {
        for await event in socket.events {
            for frame in socket.process(event) {
                decode(frame.payload)      // MPEG-TS, 1316 bytes at a time
            }
        }
    }
}

manager.addListener(endpoint: IPv4Address("0.0.0.0")!, port: 9000, passphrase: "correct-horse-battery")
manager.connect(to: IPv4Address("10.0.0.5")!, port: 9000, streamId: nil, passphrase: "correct-horse-battery")
```

To send, hand `socket.outbound` to whatever produces data; it is safe to use
from any thread, and payloads are packetized on the owner's task:

```swift
socket.outbound.send(transportStreamChunk)
```

Every socket exposes `statistics`: packets received, lost, retransmitted,
dropped, RTT, latency, ACK and NAK counts, and the same for the send side.

## Targets

- `SwiftSrt` -- the transport.
- `SwiftSrtMedia` -- `TsDemuxer`, `H264SampleBuilder`, `SrtVideoRenderer`,
  `SrtVideoView` (SwiftUI, AppKit and UIKit), `SrtPlayer`.
- `SrtNetem` -- a UDP proxy that drops and reorders on purpose, for tests.
- `srt-receive`, `srt-send`, `srt-player`, `srt-netem`, `srt-testpattern` --
  command-line tools built on the above.

## Try it

You need libsrt's tools as the other end: `brew install srt`. The player and
`srt-receive` listen; `srt-live-transmit` calls them.

```sh
swift build

# a 60 s test clip with a frame counter burned in
.build/debug/srt-testpattern | ffmpeg -f rawvideo -pix_fmt bgra -s 1280x720 -r 30 -i - \
  -c:v libx264 -tune zerolatency -g 30 -pix_fmt yuv420p -f mpegts clock.ts

# 1. our player (add --passphrase on both ends for AES-128)
.build/debug/srt-player --port 9000

# 2. libsrt sends to it
srt-live-transmit "udp://:1235" "srt://127.0.0.1:9000?mode=caller&latency=200" &
ffmpeg -re -stream_loop -1 -i clock.ts -c copy -f mpegts "udp://127.0.0.1:1235?pkt_size=1316"
```

The other direction, with VLC as the receiver:

```sh
.build/debug/srt-send --from 1237 --listen 9100 &
ffmpeg -re -stream_loop -1 -i clock.ts -c copy -f mpegts "udp://127.0.0.1:1237?pkt_size=1316" &
open -a VLC srt://127.0.0.1:9100
# encrypted: add --passphrase to srt-send and use srt://127.0.0.1:9100?passphrase=...
```

Rendezvous, for two peers behind NATs, each binding a local port and calling
the other. On one machine the two sides need different ports; `port=` is
what makes `srt-live-transmit` bind its own rather than the target's:

```sh
.build/debug/srt-receive --port 9300 --rendezvous 127.0.0.1:9301 &
srt-live-transmit "udp://:1236" "srt://127.0.0.1:9300?mode=rendezvous&port=9301&latency=200"
```

To see loss handling, put `srt-netem` in the path and compare the captured
bytes with the source:

```sh
.build/debug/srt-receive --port 9100 --out capture.ts --seconds 20 &
.build/debug/srt-netem --listen 9101 --to 127.0.0.1:9100 --loss 0.05 --seed 42 &
srt-live-transmit "udp://:1236" "srt://127.0.0.1:9101?mode=caller&latency=200" &
ffmpeg -re -i clock.ts -c copy -f mpegts "udp://127.0.0.1:1236?pkt_size=1316"
cmp clock.ts capture.ts && echo identical
```

## Tests

`swift test` covers the wire format, the handshake exchange, the hardening
libsrt 1.5.7 introduced, the receive and send buffers, sequence arithmetic,
the demuxer, and the impairment proxy.

## License

MIT. Portions follow the SRT protocol specification, which is licensed under
the Mozilla Public License 2.0.
