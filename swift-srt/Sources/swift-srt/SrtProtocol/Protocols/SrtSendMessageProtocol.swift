//
//  SrtSendMessageProtocol.swift
//  
//
//  Created by Ben Waidhofer on 6/5/24.
//

import Foundation

protocol SrtSendMessageProtocol {
    
    var ackAckCount: Int { get }
    var ackCount: Int { get }
    var duration: TimeInterval { get }
    var nackCount: Int { get }
    var totalBytes: Int { get }

    var onMessageSent: (UInt32) -> Void { get }
    var sendAckAck: (UInt32) -> Void { get }
    var sendData: (DataPacketFrame) -> Void { get }

    func handleAck (ack: AcknowledgementFrame) -> Void
    func handleNack (nack: NegativeAckFrame) -> Void

    init(
        frame: Data,
        encryptionKey: Data,
        decryptionKey: Data,
        messageId: UInt32,
        destinationSocketId: UInt32,
        sequenceNumberBase: UInt32,
        sendAckAck: @escaping (UInt32) -> Void,
        sendData: @escaping (DataPacketFrame) -> Void,
        onMessageSent: @escaping (UInt32) -> Void
    )
}
