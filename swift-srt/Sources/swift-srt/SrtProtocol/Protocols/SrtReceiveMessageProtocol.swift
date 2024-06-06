//
//  SrtReceiveMessageProtocol.swift
//
//
//  Created by Ben Waidhofer on 6/5/24.
//

import Foundation

protocol SrtReceiveMessageProtocol {
    
    var ackAckCount: Int { get }
    var ackCount: Int { get }
    var duration: TimeInterval { get }
    var nackCount: Int { get }
    var totalBytes: Int { get }

    var onMessageReceived: (UInt32, Data) -> Void { get }
    var sendAck: (UInt32) -> Void { get }
    var sendNack: ([UInt32], [(UInt32, UInt32)]) -> Void { get }

    func handleAckAck (ackAck: AckAckFrame) -> Void
    func receivePacket(packet: DataPacketFrame)

    init(
        encryptionKey: Data,
        decryptionKey: Data,
        messageId: UInt32,
        sequenceNumberBase: UInt32,
        onMessageReceived: @escaping (UInt32, Data) -> Void,
        sendAck: @escaping (UInt32) -> Void,
        sendNack: @escaping ([UInt32], [(UInt32, UInt32)]) -> Void
    )
}
