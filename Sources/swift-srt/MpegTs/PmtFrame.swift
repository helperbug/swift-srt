import Foundation

/// PMT packets contain information about the programs in the transport stream.
public struct PmtFrame {
    
    public let data: Data
    public let header: MpegTsHeader
    
    /// Table ID should always be 0x02 for PMT
    public var tableId: UInt8 {
        return data[5]
    }
    
    public var sectionSyntaxIndicator: Bool {
        return (data[6] & 0x80) != 0
    }
    
    public var sectionLength: UInt16 {
        return (UInt16(data[6] & 0x0F) << 8) | UInt16(data[7])
    }
    
    public var programNumber: UInt16 {
        return (UInt16(data[8]) << 8) | UInt16(data[9])
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
    
    public var pcrPid: UInt16 {
        return (UInt16(data[13] & 0x1F) << 8) | UInt16(data[14])
    }
    
    public var programInfoLength: UInt16 {
        return (UInt16(data[15] & 0x0F) << 8) | UInt16(data[16])
    }
    
    public var elementaryStreamInfos: [(streamType: UInt8, elementaryPid: UInt16, esInfoLength: UInt16)] {
        var infos: [(streamType: UInt8, elementaryPid: UInt16, esInfoLength: UInt16)] = []
        var offset = 17 + Int(programInfoLength)
        while offset < data.count - 4 {
            let streamType = data[offset]
            let elementaryPid = (UInt16(data[offset + 1] & 0x1F) << 8) | UInt16(data[offset + 2])
            let esInfoLength = (UInt16(data[offset + 3] & 0x0F) << 8) | UInt16(data[offset + 4])
            infos.append((streamType, elementaryPid, esInfoLength))
            offset += 5 + Int(esInfoLength)
        }
        return infos
    }
    
    /// Constructor used by the receive network path
    public init?(_ bytes: Data, pid: UInt16) {
        guard bytes.count == 188 else {
            return nil
        }

        self.data = bytes
        
        guard let header = MpegTsHeader(data: bytes, pid: pid) else {
            return nil
        }
        
        self.header = header

        guard header.syncByte == 0x47 else {
            return nil
        }

        guard header.pid == pid else {
            print("not a pmt \(header.pid) != \(pid)")
            return nil
        }

        guard tableId == 0x02 else {
            return nil
        }

        // Assuming a function MpegTsParser.verifyCRC exists to check CRC
//        guard MpegTsParser.verifyCRC(data) else {
//            return nil
//        }
    }
    
    public func makePacket(socketId: UInt32) -> SrtPacket {
        SrtPacket(
            isData: true,
            field1: ControlTypes.shutdown.asField,
            socketID: socketId,
            contents: self.data
        )
    }
}

public extension PmtFrame {
    var debugDescription: String {
        return """
        PmtFrame:
          - tableId: \(tableId)
          - sectionSyntaxIndicator: \(sectionSyntaxIndicator)
          - sectionLength: \(sectionLength)
          - programNumber: \(programNumber)
          - versionNumber: \(versionNumber)
          - currentNextIndicator: \(currentNextIndicator)
          - sectionNumber: \(sectionNumber)
          - lastSectionNumber: \(lastSectionNumber)
          - pcrPid: \(pcrPid)
          - programInfoLength: \(programInfoLength)
          - elementaryStreamInfos: \(elementaryStreamInfos)
        """
    }
}
