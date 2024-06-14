public enum ControlTypes: UInt16 {
    case handshake = 0x0000
    case keepAlive = 0x0001
    case acknowledgement = 0x0002
    case negativeAcknowledgement = 0x0003
    case congestionWarning = 0x0004
    case shutdown = 0x0005
    case ackack = 0x0006
    case dropRequest = 0x0007
    case peerError = 0x0008
    case userDefined = 0x7FFF
    case none = 0xFFFF
    
    var asField: UInt32 {
        return UInt32(self.rawValue) << 16
    }
}

