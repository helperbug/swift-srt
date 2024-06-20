
import Foundation

public struct MpegTsHeader {
    public let syncByte: UInt8
    public let transportErrorIndicator: Bool
    public let payloadUnitStartIndicator: Bool
    public let transportPriority: Bool
    public let pid: UInt16
    public let transportScramblingControl: TransportScramblingControlTypes
    public let adaptationFieldControl: AdaptationFieldControlTypes
    public let continuityCounter: UInt8
    public let adaptationField: AdaptationField?
    public let payload: Data?
    
    public struct AdaptationField {
        public let adaptationFieldLength: UInt8
        public let discontinuityIndicator: Bool
        public let randomAccessIndicator: Bool
        public let elementaryStreamPriorityIndicator: Bool
        public let pcrFlag: Bool
        public let opcrFlag: Bool
        public let splicingPointFlag: Bool
        public let transportPrivateDataFlag: Bool
        public let adaptationFieldExtensionFlag: Bool
        public let pcr: UInt64?
        public let opcr: UInt64?
        public let spliceCountdown: Int8?
        public let transportPrivateDataLength: UInt8?
        public let transportPrivateData: Data?
        public let adaptationExtension: AdaptationExtension?
        public let stuffingBytes: Data?
        
        public struct AdaptationExtension {
            public let adaptationExtensionLength: UInt8
            public let ltwFlag: Bool
            public let piecewiseRateFlag: Bool
            public let seamlessSpliceFlag: Bool
            public let ltwValidFlag: Bool?
            public let ltwOffset: UInt16?
            public let piecewiseRate: UInt32?
            public let spliceType: UInt8?
            public let dtsNextAccessUnit: UInt64?
        }
    }
    
    public init?(data: Data, pid: uint16) {
        guard data.count >= 4 else { return nil }
        
        self.pid = ((UInt16(data[1] & 0x1F) << 8) | UInt16(data[2]))

        if self.pid != pid {
            return nil
        }

        self.syncByte = data[0]
        self.transportErrorIndicator = (data[1] & 0x80) != 0
        self.payloadUnitStartIndicator = (data[1] & 0x40) != 0
        self.transportPriority = (data[1] & 0x20) != 0
        self.transportScramblingControl = .init(rawValue: (data[3] & 0xC0) >> 6) ?? .notScrambled
        self.adaptationFieldControl = .init(rawValue: (data[3] & 0x30) >> 4) ?? .payloadOnly
        self.continuityCounter = data[3] & 0x0F
        
        
        var offset = 4
        var adaptationField: AdaptationField? = nil
        var payload: Data? = nil
        
        if adaptationFieldControl == .adaptationFieldOnly || adaptationFieldControl == .adaptationFieldFollowedByPayload {
            guard data.count > offset else { return nil }
            
            let adaptationFieldLength = data[offset]
            offset += 1
            
            guard data.count >= offset + Int(adaptationFieldLength) else { return nil }
            
            let flags = data[offset]
            offset += 1
            
            let discontinuityIndicator = (flags & 0x80) != 0
            let randomAccessIndicator = (flags & 0x40) != 0
            let elementaryStreamPriorityIndicator = (flags & 0x20) != 0
            let pcrFlag = (flags & 0x10) != 0
            let opcrFlag = (flags & 0x08) != 0
            let splicingPointFlag = (flags & 0x04) != 0
            let transportPrivateDataFlag = (flags & 0x02) != 0
            let adaptationFieldExtensionFlag = (flags & 0x01) != 0
            
            var remainingLength = Int(adaptationFieldLength) - 1
            
            var pcr: UInt64? = nil
            var opcr: UInt64? = nil
            var spliceCountdown: Int8? = nil
            var transportPrivateDataLength: UInt8? = nil
            var transportPrivateData: Data? = nil
            var adaptationExtension: AdaptationField.AdaptationExtension? = nil
            var stuffingBytes: Data? = nil
            
            if pcrFlag, remainingLength >= 6 {
                pcr = UInt64(data[offset]) << 25 |
                      UInt64(data[offset + 1]) << 17 |
                      UInt64(data[offset + 2]) << 9 |
                      UInt64(data[offset + 3]) << 1 |
                      UInt64(data[offset + 4]) >> 7
                offset += 6
                remainingLength -= 6
            }
            
            if opcrFlag, remainingLength >= 6 {
                opcr = UInt64(data[offset]) << 25 |
                       UInt64(data[offset + 1]) << 17 |
                       UInt64(data[offset + 2]) << 9 |
                       UInt64(data[offset + 3]) << 1 |
                       UInt64(data[offset + 4]) >> 7
                offset += 6
                remainingLength -= 6
            }
            
            if splicingPointFlag, remainingLength >= 1 {
                spliceCountdown = Int8(bitPattern: data[offset])
                offset += 1
                remainingLength -= 1
            }
            
            if transportPrivateDataFlag, remainingLength >= 1 {
                transportPrivateDataLength = data[offset]
                offset += 1
                remainingLength -= 1
                
                if remainingLength >= Int(transportPrivateDataLength ?? 0) {
                    transportPrivateData = data.subdata(in: offset..<offset + Int(transportPrivateDataLength!))
                    offset += Int(transportPrivateDataLength!)
                    remainingLength -= Int(transportPrivateDataLength!)
                }
            }
            
            if adaptationFieldExtensionFlag, remainingLength >= 1 {
                let adaptationExtensionLength = data[offset]
                offset += 1
                remainingLength -= 1
                
                let extensionFlags = data[offset]
                offset += 1
                remainingLength -= 1
                
                let ltwFlag = (extensionFlags & 0x80) != 0
                let piecewiseRateFlag = (extensionFlags & 0x40) != 0
                let seamlessSpliceFlag = (extensionFlags & 0x20) != 0
                
                var ltwValidFlag: Bool? = nil
                var ltwOffset: UInt16? = nil
                var piecewiseRate: UInt32? = nil
                var spliceType: UInt8? = nil
                var dtsNextAccessUnit: UInt64? = nil
                
                if ltwFlag, remainingLength >= 2 {
                    ltwValidFlag = (data[offset] & 0x80) != 0
                    ltwOffset = UInt16(data[offset] & 0x7F) << 8 | UInt16(data[offset + 1])
                    offset += 2
                    remainingLength -= 2
                }
                
                if piecewiseRateFlag, remainingLength >= 3 {
                    piecewiseRate = UInt32(data[offset] & 0x3F) << 16 |
                                    UInt32(data[offset + 1]) << 8 |
                                    UInt32(data[offset + 2])
                    offset += 3
                    remainingLength -= 3
                }
                
                if seamlessSpliceFlag, remainingLength >= 5 {
                    spliceType = data[offset] >> 4
                    dtsNextAccessUnit = UInt64(data[offset] & 0x0E) << 29 |
                                        UInt64(data[offset + 1]) << 22 |
                                        UInt64(data[offset + 2]) << 15 |
                                        UInt64(data[offset + 3]) << 7 |
                                        UInt64(data[offset + 4]) >> 1
                    offset += 5
                    remainingLength -= 5
                }
                
                adaptationExtension = AdaptationField.AdaptationExtension(
                    adaptationExtensionLength: adaptationExtensionLength,
                    ltwFlag: ltwFlag,
                    piecewiseRateFlag: piecewiseRateFlag,
                    seamlessSpliceFlag: seamlessSpliceFlag,
                    ltwValidFlag: ltwValidFlag,
                    ltwOffset: ltwOffset,
                    piecewiseRate: piecewiseRate,
                    spliceType: spliceType,
                    dtsNextAccessUnit: dtsNextAccessUnit
                )
            }
            
            if remainingLength > 0 {
                stuffingBytes = data.subdata(in: offset..<offset + remainingLength)
                offset += remainingLength
            }
            
            adaptationField = AdaptationField(
                adaptationFieldLength: adaptationFieldLength,
                discontinuityIndicator: discontinuityIndicator,
                randomAccessIndicator: randomAccessIndicator,
                elementaryStreamPriorityIndicator: elementaryStreamPriorityIndicator,
                pcrFlag: pcrFlag,
                opcrFlag: opcrFlag,
                splicingPointFlag: splicingPointFlag,
                transportPrivateDataFlag: transportPrivateDataFlag,
                adaptationFieldExtensionFlag: adaptationFieldExtensionFlag,
                pcr: pcr,
                opcr: opcr,
                spliceCountdown: spliceCountdown,
                transportPrivateDataLength: transportPrivateDataLength,
                transportPrivateData: transportPrivateData,
                adaptationExtension: adaptationExtension,
                stuffingBytes: stuffingBytes
            )
        }
        
        if adaptationFieldControl == .payloadOnly || adaptationFieldControl == .adaptationFieldFollowedByPayload {
            payload = data.subdata(in: offset..<data.count)
        }
        
        self.adaptationField = adaptationField
        self.payload = payload
    }
}

extension MpegTsHeader {
    public var debugDescription: String {
        return """
            MpegTsHeader:
              - syncByte: \(syncByte)
              - transportErrorIndicator: \(transportErrorIndicator)
              - payloadUnitStartIndicator: \(payloadUnitStartIndicator)
              - transportPriority: \(transportPriority)
              - pid: \(pid)
              - transportScramblingControl: \(transportScramblingControl)
              - adaptationFieldControl: \(adaptationFieldControl)
              - continuityCounter: \(continuityCounter)
              - adaptationField: \(adaptationField)
              - adaptationExtension: \(adaptationField)
              - payload: \(payload)
            """
    }
}
