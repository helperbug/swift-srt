
import Foundation

public struct PATFrame {
    public let data: Data
    public let header: MpegTsHeader
    
    public var pointerField: UInt8 {
        return data[4]
    }
    
    public var tableId: UInt8 {
        return data[5]
    }
    
    public var sectionSyntaxIndicator: Bool {
        return (data[6] & 0x80) != 0
    }
    
    public var privateBit: Bool {
        return (data[6] & 0x40) != 0
    }
    
    public var reservedBits1: UInt8 {
        return (data[6] & 0x30) >> 4
    }
    
    public var sectionLength: UInt16 {
        return (UInt16(data[6] & 0x0F) << 8) | UInt16(data[7])
    }
    
    public var transportStreamId: UInt16 {
        return (UInt16(data[8]) << 8) | UInt16(data[9])
    }
    
    public var reservedBits2: UInt8 {
        return (data[10] & 0xC0) >> 6
    }
    
    public var versionNumber: UInt8 {
        return (data[10] & 0x3E) >> 1
    }
    
    public var currentNextIndicator: Bool {
        return (data[10] & 0x01) != 0
    }
    
    public var sectionNumber: UInt8 {
        return data[11]
    }
    
    public var lastSectionNumber: UInt8 {
        return data[12]
    }
    
    public var programInfo: [(programNumber: UInt16, pid: UInt16)] {
        var info = [(programNumber: UInt16, pid: UInt16)]()
        let sectionEnd = 5 + sectionLength - 4
        var i = 13
        while i < sectionEnd {
            let programNumber = (UInt16(data[i]) << 8) | UInt16(data[i+1])
            let pid = (UInt16(data[i+2] & 0x1F) << 8) | UInt16(data[i+3])
            info.append((programNumber, pid))
            i += 4
        }
        return info
    }
    
    public var crc32: UInt32 {
        return (UInt32(data[data.count-4]) << 24) | (UInt32(data[data.count-3]) << 16) | (UInt32(data[data.count-2]) << 8) | UInt32(data[data.count-1])
    }
    
    public init?(_ bytes: Data) {
        guard let header = MpegTsHeader(data: bytes, pid: 0) else {
            return nil
        }
        
        self.header = header
        self.data = bytes
        
        guard header.syncByte == 0x47 else {
            return nil
        }
        
        guard header.pid == 0x0000 else {
            print("bouncing pid \(header.pid)")
            return nil
        }
        
        guard tableId == 0x00 else {
            return nil
        }
        
        guard sectionSyntaxIndicator else {
            return nil
        }
        
        guard !privateBit else {
            return nil
        }
        
        guard reservedBits1 == 0x03 else {
            return nil
        }
        
        guard reservedBits2 == 0x03 else {
            return nil
        }
        
//        guard MpegTsParser.verifyCRC(data) else {
//            return nil
//        }
    }
}

extension PATFrame {
    var debugDescription: String {
        return """
            PATFrame:
              - tableId: \(tableId)
              - sectionSyntaxIndicator: \(sectionSyntaxIndicator)
              - privateBit: \(privateBit)
              - reservedBits1: \(reservedBits1)
              - sectionLength: \(sectionLength)
              - transportStreamId: \(transportStreamId)
              - reservedBits2: \(reservedBits2)
              - versionNumber: \(versionNumber)
              - currentNextIndicator: \(currentNextIndicator)
              - sectionNumber: \(sectionNumber)
              - lastSectionNumber: \(lastSectionNumber)
              - programInfo: \(programInfo)
              - crc32: \(crc32)
            """
    }
}
