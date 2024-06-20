import Foundation

struct MpegTsParser {
    static func parseTSChunks(from data: Data) -> [Data] {
        var chunks = [Data]()
        let chunkSize = 188
        var offset = data.firstIndex(of: 0x47) ?? 0
        
        while offset + chunkSize <= data.count {
            if data[offset] == 0x47 {
                let chunk = data.subdata(in: offset..<offset + chunkSize)
                chunks.append(chunk)
                offset += chunkSize
            } else {
                offset += 1
            }
        }
        
        var chunkCount = 0
        
        chunks.forEach { chunk in
            
            print("Chunk count \(chunkCount)")
            chunkCount += 1
            
            if let patFrame = PATFrame(chunk) {
                print("\(patFrame.header.debugDescription)")
            } else if let pmtFrame = PmtFrame(chunk, pid: 4096) {
                print("\(pmtFrame.header.debugDescription)")
            } else {
                
            }
        }
        
        return chunks
    }
    
    static func verifyCRC(_ data: Data) -> Bool {
        let sectionData = data.prefix(data.count - 4)
        let crcFromPacket = data.suffix(4).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        
        let computedCRC = computeCRC32(sectionData)
        return crcFromPacket == computedCRC
    }
    
    private static func computeCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        
        for byte in data {
            crc ^= UInt32(byte) << 24
            for _ in 0..<8 {
                if crc & 0x80000000 != 0 {
                    crc = (crc << 1) ^ 0x04C11DB7
                } else {
                    crc = crc << 1
                }
            }
        }
        
        return ~crc
    }
}
