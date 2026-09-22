//
//  UdpProxy.swift
//  swift-srt
//
//  A bidirectional UDP proxy that drops and reorders datagrams on purpose.
//  Put it between an SRT sender and receiver to see what loss does.
//

import Foundation
import Network
import Synchronization

public final class UdpProxy: Sendable {

    public enum Direction: Sendable, CaseIterable {
        /// From the peer that connected to us, toward the target.
        case toTarget
        /// From the target, back toward the peer.
        case fromTarget
    }

    public struct Counters: Sendable, Equatable {
        public var forwarded = 0
        public var dropped = 0
        public var reordered = 0
        public var bytes = 0
    }

    public struct Stats: Sendable, Equatable {
        public var toTarget = Counters()
        public var fromTarget = Counters()
        public var flows = 0

        public subscript(direction: Direction) -> Counters {
            get { direction == .toTarget ? toTarget : fromTarget }
            set { if direction == .toTarget { toTarget = newValue } else { fromTarget = newValue } }
        }
    }

    public let listenPort: UInt16
    public let targetHost: String
    public let targetPort: UInt16
    public let profile: ImpairmentProfile
    public let seed: UInt64

    /// Counters shared by every flow. A class, because `Mutex` cannot be
    /// copied into each flow; they all hold this one reference.
    final class SharedStats: Sendable {
        let values = Mutex(Stats())
    }

    private let queue = DispatchQueue(label: "srt.netem", qos: .userInitiated)
    private let listener: Mutex<NWListener?> = Mutex(nil)
    private let flows: Mutex<[Flow]> = Mutex([])
    private let stats = SharedStats()

    public init(listenPort: UInt16, targetHost: String, targetPort: UInt16, profile: ImpairmentProfile, seed: UInt64) {
        self.listenPort = listenPort
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.profile = profile
        self.seed = seed
    }

    public func start() throws {
        let listener = try NWListener(using: .udp, on: NWEndpoint.Port(integerLiteral: listenPort))

        listener.newConnectionHandler = { [weak self] inbound in
            self?.accept(inbound)
        }

        listener.start(queue: queue)
        self.listener.withLock { $0 = listener }
    }

    public func stop() {
        listener.withLock { $0?.cancel(); $0 = nil }
        flows.withLock { flows in
            for flow in flows { flow.cancel() }
            flows.removeAll()
        }
    }

    public var snapshot: Stats {
        stats.values.withLock { $0 }
    }

    /// Each remote endpoint gets its own outbound socket so the target sees a
    /// distinct source port per flow, as it would with real peers.
    private func accept(_ inbound: NWConnection) {

        let outbound = NWConnection(host: NWEndpoint.Host(targetHost),
                                    port: NWEndpoint.Port(integerLiteral: targetPort),
                                    using: .udp)

        let index = stats.values.withLock { stats -> Int in
            stats.flows += 1
            return stats.flows
        }

        /// A distinct seed per flow, derived from the run's seed, keeps runs
        /// reproducible while keeping flows independent.
        let flow = Flow(inbound: inbound,
                        outbound: outbound,
                        impairment: Impairment(profile: profile, seed: seed &+ UInt64(index)),
                        stats: stats)

        flows.withLock { $0.append(flow) }

        inbound.start(queue: queue)
        outbound.start(queue: queue)
        flow.pump(.toTarget)
        flow.pump(.fromTarget)
    }

    /// One inbound/outbound pair and the state needed to impair it.
    final class Flow: Sendable {

        private let inbound: NWConnection
        private let outbound: NWConnection
        private let impairment: Mutex<Impairment>
        private let held: Mutex<[Direction: Data]> = Mutex([:])
        private let stats: SharedStats

        init(inbound: NWConnection, outbound: NWConnection, impairment: Impairment, stats: SharedStats) {
            self.inbound = inbound
            self.outbound = outbound
            self.impairment = Mutex(impairment)
            self.stats = stats
        }

        func cancel() {
            inbound.cancel()
            outbound.cancel()
        }

        func pump(_ direction: Direction) {

            let from = direction == .toTarget ? inbound : outbound
            let to = direction == .toTarget ? outbound : inbound

            from.receiveMessage { [weak self] data, _, _, error in

                guard let self, error == nil else { return }

                if let data, !data.isEmpty {
                    self.relay(data, direction: direction, to: to)
                }

                self.pump(direction)
            }
        }

        private func relay(_ data: Data, direction: Direction, to: NWConnection) {

            let decision = impairment.withLock { $0.decide() }

            switch decision {
            case .drop:
                stats.values.withLock { $0[direction].dropped += 1 }

            case .hold:
                /// Hold at most one; a second hold while one is pending just forwards.
                let alreadyHeld = held.withLock { held -> Bool in
                    if held[direction] == nil {
                        held[direction] = data
                        return false
                    }
                    return true
                }
                if alreadyHeld {
                    forward(data, direction: direction, to: to)
                }

            case .forward:
                forward(data, direction: direction, to: to)

                /// Anything held goes out behind this one: that is the reorder.
                if let delayed = held.withLock({ $0.removeValue(forKey: direction) }) {
                    forward(delayed, direction: direction, to: to)
                    stats.values.withLock { $0[direction].reordered += 1 }
                }
            }
        }

        private func forward(_ data: Data, direction: Direction, to: NWConnection) {
            to.send(content: data, completion: .idempotent)
            stats.values.withLock { stats in
                stats[direction].forwarded += 1
                stats[direction].bytes += data.count
            }
        }
    }
}
