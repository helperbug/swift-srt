//
//  SrtSocketContext
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

import Foundation

/// Everything the receiver reports about one socket.
public struct SrtSocketStatistics: Sendable, Equatable {
    public var buffer = ReceiveBuffer.Statistics()
    public var send = SendBuffer.Statistics()
    public var acksReceived = 0
    public var naksReceived = 0
    public var ackAcksSent = 0
    public var dropRequestsSent = 0
    public var keepAlivesSent = 0
    public var peerRttMicroseconds: UInt32 = 0
    public var peerAvailableBuffer: UInt32 = 0
    public var flowWindowDrops = 0
    public var encryptedPackets = 0
    public var decryptedPackets = 0
    public var undecryptablePackets = 0
    public var rttMicroseconds: UInt32 = 0
    public var rttVarianceMicroseconds: UInt32 = 0
    public var latencyMicroseconds: UInt32 = 0
    public var acksSent = 0
    public var lightAcksSent = 0
    public var naksSent = 0
    public var ackAcksReceived = 0
    public var keepAlivesAnswered = 0
    public var dropRequestsReceived = 0
    public var receiveRatePacketsPerSecond = 0
    public var receiveRateBytesPerSecond = 0
    public var ticks = 0
    public var ticksWithNothingToAck = 0
    public var driftMicroseconds: Int32 = 0
    public var driftCorrections = 0
}

/// Protocol state for one socket. Owned by that socket's receive task and
/// never shared; nothing here is Sendable and nothing needs to be.
///
/// Receive side of SRT: reorders through `ReceiveBuffer`, acknowledges on
/// the 10 ms tick, reports loss immediately and again every NAK interval,
/// measures RTT from ACKACKs, releases packets on TSBPD time, and drops what
/// is too late to matter.
public final class SrtSocketContext {

    public let id = UUID()

    /// This socket's own ID. The peer puts it in the destination field of every
    /// packet it sends here, so inbound packets are matched on it.
    public let socketId: UInt32

    /// The peer's socket ID, used as the destination on everything sent back.
    public let peerSocketId: UInt32

    public let encrypted: Bool
    public let synCookie: UInt32

    /// Installed by the connection when the socket is registered.
    var clock = SrtClock()

    // -- negotiated by the handshake --
    /// The peer's ISN: where our receive buffer starts.
    public var initialPacketSequenceNumber: UInt32 = 0
    /// Our ISN: where our first data packet starts.
    public var ownInitialSequenceNumber: UInt32 = 0
    /// Largest payload per data packet, from the negotiated MSS.
    public var payloadSize = 1316
    public var srtVersion: UInt32?
    public var srtFlags: UInt32?
    public var receiverTsbpdDelay: UInt16?
    public var senderTsbpdDelay: UInt16?
    public var streamId: String?

    /// Stream keys from the handshake; nil runs in the clear.
    var encryption: SrtEncryption?

    // -- send state --
    private var sendBuffer: SendBuffer?
    private var lastSent: UInt32 = 0
    private var peerRtt = RttEstimator()

    // -- receive state --
    private var buffer: ReceiveBuffer?
    private var rtt = RttEstimator()

    private var acknowledgementNumber: UInt32 = 0
    private var acknowledgementsInFlight: [UInt32: UInt32] = [:]
    private var lastAcknowledgedSequence: UInt32?
    private var lastFullAck: UInt32 = 0
    private var packetsSinceLightAck = 0

    private var rateWindowStart: UInt32 = 0
    private var rateWindowPackets = 0
    private var rateWindowBytes = 0
    private var receiveRatePackets = 0
    private var receiveRateBytes = 0

    public private(set) var statistics = SrtSocketStatistics()

    /// Light ACKs go out every this many packets between full ones.
    private static let lightAckEvery = 64
    /// How many un-answered ACKs to keep round-trip timing for.
    private static let maximumAcksInFlight = 256
    /// Anything beyond this is a wrapped or reordered timestamp, not a round trip.
    private static let maximumPlausibleRtt: UInt32 = 10_000_000
    /// Default receiver latency when the handshake did not say.
    private static let defaultLatencyMilliseconds: UInt16 = 120
    /// Send a keep-alive after this long without sending anything else.
    private static let keepAliveInterval: UInt32 = 1_000_000
    /// Grace added to the latency before the sender gives up on a packet, as
    /// libsrt's send-drop delay does; an ACK a few ms late is not a loss.
    private static let sendDropGrace: UInt32 = 20_000

    init(encrypted: Bool, socketId: UInt32, peerSocketId: UInt32 = 0, synCookie: UInt32) {
        self.encrypted = encrypted
        self.socketId = socketId
        self.peerSocketId = peerSocketId
        self.synCookie = synCookie
    }

    /// Called once the handshake has filled in the delays and the peer's ISN.
    func activate() {
        let ours = receiverTsbpdDelay ?? Self.defaultLatencyMilliseconds
        let theirs = senderTsbpdDelay ?? 0
        let latency = UInt32(max(ours, theirs)) * 1_000
        buffer = ReceiveBuffer(initialSequence: initialPacketSequenceNumber, latencyMicroseconds: latency)
        sendBuffer = SendBuffer(initialSequence: ownInitialSequenceNumber)
        statistics.latencyMicroseconds = latency
        lastFullAck = clock.now
        lastSent = clock.now
        rateWindowStart = clock.now
    }

    // MARK: Events

    func handle(event: SrtSocketEvent,
                header: UdpHeader,
                send: (SrtPacket, Data) -> Void,
                metrics: SrtMetricsServiceProtocol,
                deliver: (SrtFrame) -> Void) {

        switch event {
        case .packet(let packet):
            if packet.isData {
                handleData(packet, header: header, send: send, metrics: metrics, deliver: deliver)
            } else {
                handleControl(packet, header: header, send: send, metrics: metrics)
            }

        case .tick(let now):
            tick(now: now, header: header, send: send, metrics: metrics, deliver: deliver)

        case .send(let payload):
            transmit(payload, header: header, send: send, metrics: metrics)
        }
    }

    // MARK: Sending data

    /// One payload becomes one message, split into packets of at most
    /// `payloadSize` with the position bits marking first/middle/last/only.
    private func transmit(_ payload: Data,
                          header: UdpHeader,
                          send: (SrtPacket, Data) -> Void,
                          metrics: SrtMetricsServiceProtocol) {

        guard sendBuffer != nil, !payload.isEmpty else { return }

        /// The peer's last ACK said how much room it has. Past that, a new
        /// packet would only be dropped at the far end; drop it here instead
        /// and count it, so the pressure is visible.
        if statistics.peerAvailableBuffer > 0, sendBuffer!.count >= Int(statistics.peerAvailableBuffer) {
            statistics.flowWindowDrops += 1
            return
        }

        let chunks = stride(from: 0, to: payload.count, by: payloadSize).map { start in
            payload.subdata(in: start..<min(start + payloadSize, payload.count))
        }

        var bytes = 0
        var message: UInt32 = 0

        for (index, chunk) in chunks.enumerated() {
            /// Every packet takes a sequence number; only the first takes a
            /// message number, which the rest of the message shares.
            let allocated = sendBuffer!.allocate(message: index == 0)
            let sequence = allocated.sequence
            if index == 0 { message = allocated.message }
            let position: UInt8 = chunks.count == 1 ? 0b11 : (index == 0 ? 0b10 : (index == chunks.count - 1 ? 0b01 : 0b00))
            let now = clock.now

            var body = chunk
            var keyFlags: UInt8 = 0
            if let encryption {
                guard let sealed = encryption.encrypt(chunk, sequence: sequence) else { continue }
                body = sealed
                keyFlags = KeyMaterialFrame.KeyFlags.even.rawValue
                statistics.encryptedPackets += 1
            }

            let packet = DataPacketFrame(
                packetSequenceNumber: sequence,
                packetPosition: position,
                orderFlag: false,
                encryptionFlags: keyFlags,
                retransmittedFlag: false,
                messageNumber: message,
                timestamp: now,
                destinationSocketID: peerSocketId,
                payload: body,
                authenticationTag: Data()
            )

            send(SrtPacket(data: packet.data.prefix(16)), body)
            sendBuffer!.store(packet, sent: now)
            bytes += chunk.count
            lastSent = now
        }

        statistics.send = sendBuffer!.statistics
        metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                  send: SrtMetricsModel(bytesCount: bytes, dataPacketCount: chunks.count))
    }

    private func retransmit(_ packet: DataPacketFrame, send: (SrtPacket, Data) -> Void) {
        send(SrtPacket(data: packet.data.prefix(16)), packet.payload)
        lastSent = clock.now
    }

    // MARK: Data

    private func handleData(_ packet: SrtPacket,
                            header: UdpHeader,
                            send: (SrtPacket, Data) -> Void,
                            metrics: SrtMetricsServiceProtocol,
                            deliver: (SrtFrame) -> Void) {

        guard buffer != nil, let dataPacket = DataPacketFrame(packet.data) else { return }

        let now = clock.now
        let result = buffer!.insert(dataPacket, arrival: now)

        guard result == .stored else { return }

        rateWindowPackets += 1
        rateWindowBytes += dataPacket.payload.count

        /// Loss is reported the moment it is noticed; the periodic NAK on the
        /// tick covers anything still missing after that.
        let fresh = buffer!.lossesToReport(now: now, interval: UInt32.max)
        if !fresh.isEmpty {
            sendNak(fresh, header: header, send: send, metrics: metrics)
        }

        packetsSinceLightAck += 1
        if packetsSinceLightAck >= Self.lightAckEvery {
            sendLightAck(header: header, send: send, metrics: metrics)
        }

        release(now: now, header: header, metrics: metrics, deliver: deliver)
    }

    // MARK: Tick

    private func tick(now: UInt32,
                      header: UdpHeader,
                      send: (SrtPacket, Data) -> Void,
                      metrics: SrtMetricsServiceProtocol,
                      deliver: (SrtFrame) -> Void) {

        guard buffer != nil else { return }
        statistics.ticks += 1

        /// Anything whose time has come, including giving up on a hole that
        /// the packet behind it has already outwaited.
        buffer!.dropExpired(now: now)
        release(now: now, header: header, metrics: metrics, deliver: deliver)

        /// The tick is the SYN interval, so a full ACK goes out on every tick
        /// that has something new to say -- the same rule libsrt applies.
        let ackSequence = buffer!.acknowledgeSequence
        if ackSequence != lastAcknowledgedSequence {
            sendFullAck(ackSequence, now: now, header: header, send: send, metrics: metrics)
        } else {
            statistics.ticksWithNothingToAck += 1
        }

        /// Re-ask for whatever is still missing, paced by the round trip.
        let overdue = buffer!.lossesToReport(now: now, interval: rtt.nakInterval)
        if !overdue.isEmpty {
            sendNak(overdue, header: header, send: send, metrics: metrics)
        }

        /// Sender side: give up on packets the receiver could no longer use,
        /// and tell it so it stops asking.
        if let latency = buffer?.latencyMicroseconds, sendBuffer != nil {
            let expired = sendBuffer!.dropExpired(now: now, latencyMicroseconds: latency + Self.sendDropGrace)
            for range in expired {
                sendDropRequest(first: range.first, last: range.last, message: range.message, header: header, send: send, metrics: metrics)
            }
            if !expired.isEmpty { statistics.send = sendBuffer!.statistics }
        }

        /// Keep the flow alive from our side when we have nothing else to say.
        if SrtClock.elapsed(from: lastSent, to: now) >= Self.keepAliveInterval {
            let keepAlive = SrtPacket(field1: ControlTypes.keepAlive.asField, socketID: peerSocketId, contents: Data())
            send(keepAlive, Data())
            lastSent = now
            statistics.keepAlivesSent += 1
        }

        updateRates(now: now)
    }

    // MARK: Control

    private func handleControl(_ packet: SrtPacket,
                               header: UdpHeader,
                               send: (SrtPacket, Data) -> Void,
                               metrics: SrtMetricsServiceProtocol) {

        guard let control = ControlPacketFrame(packet.data),
              let type = ControlTypes(rawValue: control.controlType) else { return }

        switch type {
        case .keepAlive:
            let reply = SrtPacket(field1: ControlTypes.keepAlive.asField, socketID: peerSocketId, contents: Data())
            send(reply, Data())
            statistics.keepAlivesAnswered += 1

        case .ackack:
            guard let ackAck = AckAckFrame(packet.data) else { return }
            handleAckAck(ackAck)

        case .dropRequest:
            guard buffer != nil, let request = MessageDropRequestFrame(packet.data) else { return }
            buffer!.drop(from: request.firstSequenceNumber, to: request.lastSequenceNumber)
            statistics.dropRequestsReceived += 1

        case .acknowledgement:
            handleAck(packet, control: control, header: header, send: send, metrics: metrics)

        case .negativeAcknowledgement:
            handleNak(packet, header: header, send: send, metrics: metrics)

        case .congestionWarning, .peerError, .userDefined, .shutdown, .handshake, .none:
            /// Handled by the connection, or not part of live mode.
            break
        }
    }

    /// Full ACKs carry an ACK number to echo back and the peer's view of RTT
    /// and buffer; light ACKs carry only the sequence number.
    private func handleAck(_ packet: SrtPacket,
                           control: ControlPacketFrame,
                           header: UdpHeader,
                           send: (SrtPacket, Data) -> Void,
                           metrics: SrtMetricsServiceProtocol) {

        guard sendBuffer != nil else { return }
        statistics.acksReceived += 1

        let ackNumber = control.typeSpecificInformation

        if let full = AcknowledgementFrame(packet.data) {
            sendBuffer!.acknowledge(upTo: full.lastAcknowledgedPacketSequenceNumber)
            statistics.peerRttMicroseconds = full.rtt
            statistics.peerAvailableBuffer = full.availableBufferSize
            if full.rtt > 0 { peerRtt.add(sample: full.rtt) }
        } else if packet.contents.count >= 4 {
            var offset = 0
            let sequence = packet.contents.toUInt32(from: &offset) & SrtSequence.maximum
            sendBuffer!.acknowledge(upTo: sequence)
        } else {
            return
        }

        statistics.send = sendBuffer!.statistics

        /// A full ACK is answered so the peer can measure the round trip.
        if ackNumber != 0 {
            let reply = SrtPacket(field1: ControlTypes.ackack.asField, field2: ackNumber, socketID: peerSocketId, contents: Data())
            send(reply, Data())
            statistics.ackAcksSent += 1
        }
    }

    /// Loss list decoding: a lone sequence as is; a range as first with the
    /// top bit set, then last. Anything we still hold goes out again; anything
    /// we have already given up on gets a DROPREQ so the peer stops waiting.
    private func handleNak(_ packet: SrtPacket,
                           header: UdpHeader,
                           send: (SrtPacket, Data) -> Void,
                           metrics: SrtMetricsServiceProtocol) {

        guard sendBuffer != nil, let nak = NegativeAckFrame(packet.data) else { return }
        statistics.naksReceived += 1

        let words = nak.lossList
        var index = 0
        var resent = 0
        var bytes = 0

        while index < words.count {
            let word = words[index]
            let first = word & SrtSequence.maximum
            var last = first

            if word & 0x8000_0000 != 0, index + 1 < words.count {
                last = words[index + 1] & SrtSequence.maximum
                index += 2
            } else {
                index += 1
            }

            /// A hostile or confused range must not walk the whole space.
            let span = SrtSequence.length(from: first, to: last)
            guard span > 0, span <= 8192 else { continue }

            var sequence = first
            var unknownFrom: UInt32?

            for _ in 0..<span {
                if let again = sendBuffer!.retransmission(of: sequence) {
                    if let from = unknownFrom {
                        sendDropRequest(first: from, last: SrtSequence.decrement(sequence), message: 0, header: header, send: send, metrics: metrics)
                        unknownFrom = nil
                    }
                    retransmit(again, send: send)
                    resent += 1
                    bytes += again.payload.count
                } else if unknownFrom == nil {
                    unknownFrom = sequence
                }
                sequence = SrtSequence.increment(sequence)
            }

            if let from = unknownFrom {
                sendDropRequest(first: from, last: last, message: 0, header: header, send: send, metrics: metrics)
            }
        }

        statistics.send = sendBuffer!.statistics
        if resent > 0 {
            metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                      send: SrtMetricsModel(bytesCount: bytes, dataPacketCount: resent, nackCount: 1))
        }
    }

    private func sendDropRequest(first: UInt32, last: UInt32, message: UInt32,
                                 header: UdpHeader,
                                 send: (SrtPacket, Data) -> Void,
                                 metrics: SrtMetricsServiceProtocol) {
        var contents = Data(capacity: 8)
        contents.append(contentsOf: first.bytes)
        contents.append(contentsOf: last.bytes)
        let packet = SrtPacket(field1: ControlTypes.dropRequest.asField, field2: message, socketID: peerSocketId, contents: Data())
        send(packet, contents)
        lastSent = clock.now
        statistics.dropRequestsSent += 1
        metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                  send: SrtMetricsModel(bytesCount: 24, controlCount: 1))
    }

    private func handleAckAck(_ ackAck: AckAckFrame) {

        statistics.ackAcksReceived += 1

        guard let sent = acknowledgementsInFlight.removeValue(forKey: ackAck.acknowledgementNumber) else {
            return
        }

        let sample = SrtClock.elapsed(from: sent, to: clock.now)
        guard sample > 0, sample < Self.maximumPlausibleRtt else { return }

        rtt.add(sample: sample)
        statistics.rttMicroseconds = rtt.rtt
        statistics.rttVarianceMicroseconds = rtt.variance
    }

    // MARK: Sending

    private func sendFullAck(_ sequence: UInt32,
                             now: UInt32,
                             header: UdpHeader,
                             send: (SrtPacket, Data) -> Void,
                             metrics: SrtMetricsServiceProtocol) {

        acknowledgementNumber &+= 1
        if acknowledgementNumber == 0 { acknowledgementNumber = 1 }

        let ack = AcknowledgementFrame(
            isControl: true,
            controlType: .acknowledgement,
            reserved: 0,
            acknowledgementNumber: acknowledgementNumber,
            timestamp: now,
            destinationSocketID: peerSocketId,
            lastAcknowledgedPacketSequenceNumber: sequence,
            rtt: rtt.rtt,
            rttVariance: rtt.variance,
            availableBufferSize: UInt32(buffer?.availableCapacity ?? 0),
            packetsReceivingRate: UInt32(receiveRatePackets),
            estimatedLinkCapacity: UInt32(receiveRatePackets),
            receivingRate: UInt32(receiveRateBytes)
        )

        let packet = SrtPacket(field1: ControlTypes.acknowledgement.asField,
                               field2: acknowledgementNumber,
                               socketID: peerSocketId,
                               contents: Data())
        send(packet, ack.data.dropFirst(16))

        acknowledgementsInFlight[acknowledgementNumber] = now
        if acknowledgementsInFlight.count > Self.maximumAcksInFlight {
            let cutoff = acknowledgementNumber &- UInt32(Self.maximumAcksInFlight)
            acknowledgementsInFlight = acknowledgementsInFlight.filter { SrtSequence.compare($0.key, cutoff) > 0 }
        }

        lastAcknowledgedSequence = sequence
        lastFullAck = now
        packetsSinceLightAck = 0
        statistics.acksSent += 1
        metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                  send: SrtMetricsModel(ackCount: 1, bytesCount: ack.data.count, controlCount: 1))
    }

    /// A light ACK carries only the sequence number and asks for no ACKACK.
    private func sendLightAck(header: UdpHeader,
                              send: (SrtPacket, Data) -> Void,
                              metrics: SrtMetricsServiceProtocol) {

        guard let buffer else { return }

        let packet = SrtPacket(field1: ControlTypes.acknowledgement.asField, field2: 0, socketID: peerSocketId, contents: Data())
        send(packet, Data(buffer.acknowledgeSequence.bytes))

        packetsSinceLightAck = 0
        statistics.lightAcksSent += 1
        metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                  send: SrtMetricsModel(ackCount: 1, bytesCount: 20, controlCount: 1))
    }

    /// Loss list encoding: a lone sequence as is; a range as first with the
    /// top bit set, then last.
    private func sendNak(_ ranges: [ReceiveBuffer.LossRange],
                         header: UdpHeader,
                         send: (SrtPacket, Data) -> Void,
                         metrics: SrtMetricsServiceProtocol) {

        var list: [UInt32] = []
        for range in ranges {
            if range.first == range.last {
                list.append(range.first)
            } else {
                list.append(range.first | 0x8000_0000)
                list.append(range.last)
            }
            /// Keep each NAK inside one datagram.
            if list.count >= 320 { break }
        }

        var contents = Data(capacity: list.count * 4)
        for value in list { contents.append(contentsOf: value.bytes) }

        let packet = SrtPacket(field1: ControlTypes.negativeAcknowledgement.asField, socketID: peerSocketId, contents: Data())
        send(packet, contents)

        statistics.naksSent += 1
        metrics.storeSocketMetric(header: header, socketId: socketId, receive: nil,
                                  send: SrtMetricsModel(bytesCount: 16 + contents.count, controlCount: 1, nackCount: 1))
    }

    // MARK: Delivery and rates

    private func release(now: UInt32,
                         header: UdpHeader,
                         metrics: SrtMetricsServiceProtocol,
                         deliver: (SrtFrame) -> Void) {

        let ready = buffer!.drain(now: now)
        guard !ready.isEmpty else { return }

        var bytes = 0
        for packet in ready {
            var payload = packet.payload
            if packet.encryptionFlags != 0 {
                guard let encryption, let opened = encryption.decrypt(payload, sequence: packet.packetSequenceNumber) else {
                    statistics.undecryptablePackets += 1
                    continue
                }
                payload = opened
                statistics.decryptedPackets += 1
            }
            bytes += payload.count
            deliver(SrtFrame(header: header, socketId: socketId, messageId: packet.messageNumber, payload: payload))
        }

        metrics.storeSocketMetric(header: header, socketId: socketId,
                                  receive: SrtMetricsModel(bytesCount: bytes, dataPacketCount: ready.count), send: nil)
        statistics.buffer = buffer!.statistics
    }

    private func updateRates(now: UInt32) {
        let elapsed = SrtClock.elapsed(from: rateWindowStart, to: now)
        guard elapsed >= 1_000_000 else { return }
        receiveRatePackets = Int(UInt64(rateWindowPackets) * 1_000_000 / UInt64(elapsed))
        receiveRateBytes = Int(UInt64(rateWindowBytes) * 1_000_000 / UInt64(elapsed))
        statistics.receiveRatePacketsPerSecond = receiveRatePackets
        statistics.receiveRateBytesPerSecond = receiveRateBytes
        statistics.buffer = buffer?.statistics ?? statistics.buffer
        statistics.driftMicroseconds = buffer?.driftMicroseconds ?? 0
        statistics.driftCorrections = buffer?.driftCorrections ?? 0
        rateWindowStart = now
        rateWindowPackets = 0
        rateWindowBytes = 0
    }
}
