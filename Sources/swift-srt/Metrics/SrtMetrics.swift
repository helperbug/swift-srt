//
//  SrtMetrics.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Foundation

struct SrtMetrics: Sendable {

    var receiveAckAckCount = 0
    var receiveAckCount = 0
    var receiveBytesCount = 0
    var receiveControlCount = 0
    var receiveDataPacketCount = 0
    var receiveNackCount = 0
    var sendAckAckCount = 0
    var sendAckCount = 0
    var sendBytesCount = 0
    var sendControlCount = 0
    var sendDataPacketCount = 0
    var sendNackCount = 0
    var jitter: Double = 0
    var latency: Double = 0
    var roundTripTime: Double = 0

    mutating func delta(receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        if let receive {
            receiveAckAckCount += receive.ackAckCount
            receiveAckCount += receive.ackCount
            receiveBytesCount += receive.bytesCount
            receiveControlCount += receive.controlCount
            receiveDataPacketCount += receive.dataPacketCount
            receiveNackCount += receive.nackCount
        }
        if let send {
            sendAckAckCount += send.ackAckCount
            sendAckCount += send.ackCount
            sendBytesCount += send.bytesCount
            sendControlCount += send.controlCount
            sendDataPacketCount += send.dataPacketCount
            sendNackCount += send.nackCount
        }
    }

    func capture() -> (receive: SrtMetricsModel, send: SrtMetricsModel) {
        let receive = SrtMetricsModel(ackAckCount: receiveAckAckCount,
                                      ackCount: receiveAckCount,
                                      bytesCount: receiveBytesCount,
                                      controlCount: receiveControlCount,
                                      dataPacketCount: receiveDataPacketCount,
                                      jitter: jitter,
                                      latency: latency,
                                      nackCount: receiveNackCount,
                                      roundTripTime: roundTripTime)
        let send = SrtMetricsModel(ackAckCount: sendAckAckCount,
                                   ackCount: sendAckCount,
                                   bytesCount: sendBytesCount,
                                   controlCount: sendControlCount,
                                   dataPacketCount: sendDataPacketCount,
                                   jitter: jitter,
                                   latency: latency,
                                   nackCount: sendNackCount,
                                   roundTripTime: roundTripTime)
        return (receive, send)
    }
}
