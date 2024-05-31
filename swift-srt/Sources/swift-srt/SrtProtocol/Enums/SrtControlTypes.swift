public enum ControlTypes: UInt16 {
    case handshake = 0x0000
    case keepalive = 0x0001
    case ack = 0x0002
    case nak = 0x0003
    case congestionWarning = 0x0004
    case shutdown = 0x0005
    case ackack = 0x0006
    case dropreq = 0x0007
    case peererror = 0x0008
    case userDefined = 0x7FFF
    case none = 0xFFFF
}

