//
//  SrtVideoRenderer.swift
//  swift-srt
//
//  Owns the display layer and the codec state that feeds it. Everything here
//  runs on the main actor; the transport hands over plain access units.
//

#if !os(watchOS)

import AVFoundation
import CoreMedia
import Foundation
import Observation

@MainActor
@Observable
public final class SrtVideoRenderer {

    @ObservationIgnored public let layer = AVSampleBufferDisplayLayer()
    @ObservationIgnored private let renderer: AVSampleBufferVideoRenderer

    /// Our clock, attached as the layer's control timebase. The renderer's own
    /// `timebase` is read-only and runs on host time; setting it silently fails.
    @ObservationIgnored private let timebase: CMTimebase

    @ObservationIgnored private let builder = H264SampleBuilder()

    /// How far behind the stream the presentation clock runs. Frames sit in
    /// the renderer's queue for this long, so arrival jitter never reaches the
    /// screen. Zero presents each frame on its own deadline and every hiccup
    /// shows.
    @ObservationIgnored public let presentationDelay: CMTime

    /// A backwards jump larger than this is a new timeline, not jitter.
    @ObservationIgnored private let discontinuityThreshold = CMTime(value: 1, timescale: 1)

    /// If the queue gets this far ahead of the delay, the source is running
    /// faster than our clock and latency would grow without bound. Re-anchor.
    @ObservationIgnored private let driftLimit = CMTime(value: 1, timescale: 1)

    /// Within the limit, the clock is slaved to the source: it runs up to this
    /// much faster or slower to hold the queue at the target delay, which is
    /// invisible where a re-anchor would be a visible skip.
    @ObservationIgnored private let maximumRateNudge = 0.01
    @ObservationIgnored private let slavingDeadbandMs = 40.0
    @ObservationIgnored private(set) var clockRate = 1.0

    @ObservationIgnored private var anchored = false
    @ObservationIgnored private var lastPresentationTime = CMTime.invalid
    @ObservationIgnored private var lastEnqueue: ContinuousClock.Instant?
    @ObservationIgnored private var trace: FileHandle?
    @ObservationIgnored private let processStart = ContinuousClock.now

    public private(set) var framesPresented = 0
    public private(set) var framesLate = 0
    public private(set) var framesNotReady = 0
    public private(set) var discontinuities = 0
    public private(set) var reanchors = 0
    public private(set) var slackMs = RunningStats()
    public private(set) var intervalMs = RunningStats()

    public init(presentationDelayMs: Int = 150, traceURL: URL? = nil) {
        presentationDelay = CMTime(value: CMTimeValue(presentationDelayMs), timescale: 1000)
        renderer = layer.sampleBufferRenderer

        var created: CMTimebase?
        let status = CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                                     sourceClock: CMClockGetHostTimeClock(),
                                                     timebaseOut: &created)
        guard status == noErr, let created else {
            preconditionFailure("CMTimebaseCreateWithSourceClock failed: \(status)")
        }
        timebase = created

        layer.videoGravity = .resizeAspect
        CMTimebaseSetRate(timebase, rate: 1.0)
        layer.controlTimebase = timebase

        if let traceURL {
            FileManager.default.createFile(atPath: traceURL.path, contents: nil)
            trace = try? FileHandle(forWritingTo: traceURL)
            trace?.write(Data("wall_ms,pts_s,clock_s,slack_ms,interval_ms,late,ready\n".utf8))
        }
    }

    /// Builds the sample here, next to the layer that decodes it, so the buffer
    /// never has to cross an isolation boundary.
    public func render(_ unit: AccessUnit) {

        guard unit.streamType == .h264,
              let sample = (try? builder.sampleBuffer(for: unit)) ?? nil else { return }

        let now = ContinuousClock.now
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)

        /// The stream's clock went backwards: a loop, a source restart, a new
        /// encoder. Drop what is queued and start the timeline again.
        if anchored, lastPresentationTime.isValid,
           CMTimeCompare(CMTimeSubtract(lastPresentationTime, presentationTime), discontinuityThreshold) > 0 {
            renderer.flush()
            anchored = false
            discontinuities += 1
        }

        if !anchored {
            anchored = true
            CMTimebaseSetTime(timebase, time: CMTimeSubtract(presentationTime, presentationDelay))
            CMTimebaseSetRate(timebase, rate: 1.0)
        }

        let clock = CMTimebaseGetTime(timebase)
        let slackTime = CMTimeSubtract(presentationTime, clock)
        let slack = CMTimeGetSeconds(slackTime) * 1000
        let late = slack < 0
        let ready = renderer.isReadyForMoreMediaData

        /// Source running far ahead of our clock: pull the anchor forward rather
        /// than let the queue, and the latency, grow.
        if CMTimeCompare(CMTimeSubtract(slackTime, presentationDelay), driftLimit) > 0 {
            CMTimebaseSetTime(timebase, time: CMTimeSubtract(presentationTime, presentationDelay))
            reanchors += 1
        }

        /// Otherwise slave the clock: too much queued, run a touch fast; too
        /// little, a touch slow; near the target, dead on.
        let excess = slack - CMTimeGetSeconds(presentationDelay) * 1000
        let wanted: Double
        if excess > slavingDeadbandMs {
            wanted = 1.0 + maximumRateNudge
        } else if excess < -slavingDeadbandMs {
            wanted = 1.0 - maximumRateNudge
        } else {
            wanted = 1.0
        }
        if wanted != clockRate {
            CMTimebaseSetRate(timebase, rate: wanted)
            clockRate = wanted
        }

        let interval = lastEnqueue.map { TransportStats.milliseconds(now - $0) }

        slackMs.add(slack)
        if let interval { intervalMs.add(interval) }
        lastEnqueue = now
        if late { framesLate += 1 }
        if !ready { framesNotReady += 1 }

        if let trace {
            let wall = TransportStats.milliseconds(now - processStart)
            trace.write(Data(String(format: "%.1f,%.4f,%.4f,%.2f,%.2f,%d,%d\n",
                                    wall, CMTimeGetSeconds(presentationTime), CMTimeGetSeconds(clock),
                                    slack, interval ?? 0, late ? 1 : 0, ready ? 1 : 0).utf8))
        }

        if renderer.status == .failed { renderer.flush() }

        renderer.enqueue(sample)
        framesPresented += 1
        lastPresentationTime = presentationTime
    }

    public var summary: String {
        String(format: "frames %d  late %d  notReady %d  discontinuities %d  reanchors %d  rate %.3f",
               framesPresented, framesLate, framesNotReady, discontinuities, reanchors, clockRate)
    }
}

#endif
