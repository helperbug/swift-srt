//
//  H264SampleBuilder.swift
//  swift-srt
//
//  Turns H.264 access units carried in Annex B form into CMSampleBuffers that
//  AVSampleBufferDisplayLayer can decode and present.
//

import CoreMedia
import Foundation

/// The NAL unit types this package needs to recognise.
public enum NalUnitType: UInt8 {
    case nonIdrSlice = 1
    case idrSlice = 5
    case sei = 6
    case sequenceParameterSet = 7
    case pictureParameterSet = 8
    case accessUnitDelimiter = 9
}

public enum H264SampleBuilderError: Error {
    case missingParameterSets
    case formatDescriptionFailed(OSStatus)
    case blockBufferFailed(OSStatus)
    case sampleBufferFailed(OSStatus)
}

/// Accumulates parameter sets and builds decodable samples from access units.
///
/// Transport streams carry H.264 in Annex B form, with NAL units separated by
/// start codes. VideoToolbox wants AVCC: each NAL unit prefixed by its length,
/// with SPS and PPS hoisted into a format description.
public final class H264SampleBuilder {

    /// 90 kHz, the timescale MPEG-TS presentation timestamps are expressed in.
    public static let timescale: CMTimeScale = 90_000

    private var sequenceParameterSet: Data?
    private var pictureParameterSet: Data?
    private(set) public var formatDescription: CMVideoFormatDescription?

    /// Set once the first keyframe has been seen. Feeding a decoder predicted
    /// frames before any keyframe produces nothing but errors.
    private(set) public var hasKeyframe = false

    public init() { }

    /// Splits an Annex B buffer into its NAL units, without copying start codes.
    public static func nalUnits(in data: Data) -> [Data] {

        var units: [Data] = []
        let bytes = [UInt8](data)
        let count = bytes.count

        /// Offsets where a start code begins, and how long that start code is.
        var starts: [(offset: Int, length: Int)] = []
        var index = 0

        while index + 3 <= count {
            if bytes[index] == 0x00, bytes[index + 1] == 0x00 {
                if bytes[index + 2] == 0x01 {
                    starts.append((index, 3))
                    index += 3
                    continue
                }
                if index + 4 <= count, bytes[index + 2] == 0x00, bytes[index + 3] == 0x01 {
                    starts.append((index, 4))
                    index += 4
                    continue
                }
            }
            index += 1
        }

        for (position, start) in starts.enumerated() {
            let payloadStart = start.offset + start.length
            let payloadEnd = position + 1 < starts.count ? starts[position + 1].offset : count

            guard payloadStart < payloadEnd else { continue }

            units.append(Data(bytes[payloadStart..<payloadEnd]))
        }

        return units
    }

    /// Feeds one access unit and returns a sample buffer when it can build one.
    ///
    /// Parameter sets are absorbed rather than emitted, and units arriving before
    /// the first keyframe return nil.
    public func sampleBuffer(for accessUnit: AccessUnit) throws -> CMSampleBuffer? {

        let units = Self.nalUnits(in: accessUnit.data)

        guard !units.isEmpty else { return nil }

        var pictureUnits: [Data] = []
        var sawIdr = false
        var parameterSetsChanged = false

        for unit in units {

            guard let first = unit.first else { continue }

            let type = NalUnitType(rawValue: first & 0x1F)

            switch type {
            case .sequenceParameterSet:
                if sequenceParameterSet != unit {
                    sequenceParameterSet = unit
                    parameterSetsChanged = true
                }

            case .pictureParameterSet:
                if pictureParameterSet != unit {
                    pictureParameterSet = unit
                    parameterSetsChanged = true
                }

            case .accessUnitDelimiter, .sei:
                /// Not needed for decoding, and the delimiter confuses some decoders.
                continue

            case .idrSlice:
                sawIdr = true
                pictureUnits.append(unit)

            default:
                pictureUnits.append(unit)
            }
        }

        if parameterSetsChanged {
            try rebuildFormatDescription()
        }

        guard let formatDescription else { return nil }
        guard !pictureUnits.isEmpty else { return nil }

        if sawIdr {
            hasKeyframe = true
        }

        /// Without a keyframe the decoder has no reference to build from.
        guard hasKeyframe else { return nil }

        return try makeSampleBuffer(
            pictureUnits: pictureUnits,
            formatDescription: formatDescription,
            presentationTimeStamp: accessUnit.presentationTimeStamp,
            decodeTimeStamp: accessUnit.decodeTimeStamp,
            isKeyframe: sawIdr
        )
    }

    // MARK: Format description

    private func rebuildFormatDescription() throws {

        guard let sps = sequenceParameterSet, let pps = pictureParameterSet else {
            /// Both are needed; the other may still be on its way.
            return
        }

        var description: CMVideoFormatDescription?

        let status = sps.withUnsafeBytes { spsBuffer -> OSStatus in
            pps.withUnsafeBytes { ppsBuffer -> OSStatus in

                guard let spsBase = spsBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let ppsBase = ppsBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return -1
                }

                let parameterSets: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                let sizes: [Int] = [sps.count, pps.count]

                return parameterSets.withUnsafeBufferPointer { setsPointer in
                    sizes.withUnsafeBufferPointer { sizesPointer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: setsPointer.baseAddress!,
                            parameterSetSizes: sizesPointer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }

        guard status == noErr, let description else {
            throw H264SampleBuilderError.formatDescriptionFailed(status)
        }

        self.formatDescription = description
    }

    // MARK: Sample buffer

    private func makeSampleBuffer(pictureUnits: [Data],
                                  formatDescription: CMVideoFormatDescription,
                                  presentationTimeStamp: UInt64?,
                                  decodeTimeStamp: UInt64?,
                                  isKeyframe: Bool) throws -> CMSampleBuffer {

        /// AVCC: every NAL unit prefixed with its big-endian 32 bit length.
        var avcc = Data()
        for unit in pictureUnits {
            var length = UInt32(unit.count).bigEndian
            avcc.append(contentsOf: withUnsafeBytes(of: &length) { Data($0) })
            avcc.append(unit)
        }

        var blockBuffer: CMBlockBuffer?
        let totalLength = avcc.count

        /// CMBlockBuffer does not copy, so the bytes must outlive it. Hand it a
        /// block it owns rather than pointing at a Swift value.
        let memory = UnsafeMutableRawPointer.allocate(byteCount: totalLength, alignment: 1)
        avcc.withUnsafeBytes { source in
            memory.copyMemory(from: source.baseAddress!, byteCount: totalLength)
        }

        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memory,
            blockLength: totalLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: totalLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr, let blockBuffer else {
            memory.deallocate()
            throw H264SampleBuilderError.blockBufferFailed(status)
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTimeStamp.map {
                CMTime(value: CMTimeValue($0), timescale: Self.timescale)
            } ?? .invalid,
            decodeTimeStamp: decodeTimeStamp.map {
                CMTime(value: CMTimeValue($0), timescale: Self.timescale)
            } ?? .invalid
        )

        var sampleSize = totalLength
        var sampleBuffer: CMSampleBuffer?

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            throw H264SampleBuilderError.sampleBufferFailed(status)
        }

        /// Mark non-keyframes so the display layer knows it cannot start here.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(isKeyframe ? kCFBooleanFalse : kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }
}
