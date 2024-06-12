//
//  SrtMetrics.swift
//
//
//  Created by Ben Waidhofer on 6/10/24.
//

import Foundation

class SrtMetrics {
    
    var receiveAckAckCount: Int = 0
    var receiveAckCount: Int = 0
    var receiveBytesCount: Int = 0
    var receiveControlCount: Int = 0
    var receiveDataPacketCount: Int = 0
    var receiveNackCount: Int = 0

    var sendAckAckCount: Int = 0
    var sendAckCount: Int = 0
    var sendBytesCount: Int = 0
    var sendControlCount: Int = 0
    var sendDataPacketCount: Int = 0
    var sendNackCount: Int = 0

    var jitter: Double = 0
    var latency: Double = 0
    var roundTripTime: Double = 0

    func delta(receive: SrtMetricsModel?, send: SrtMetricsModel?) {
        
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
        let receiveModel = SrtMetricsModel(ackAckCount: receiveAckAckCount,
                                        ackCount: receiveAckCount,
                                        bytesCount: receiveBytesCount,
                                        controlCount: receiveControlCount,
                                        dataPacketCount: receiveDataPacketCount,
                                        jitter: jitter,
                                        latency: latency,
                                        nackCount: receiveNackCount,
                                        roundTripTime: roundTripTime)
        
        let sendModel = SrtMetricsModel(ackAckCount: sendAckAckCount,
                                        ackCount: sendAckCount,
                                        bytesCount: sendBytesCount,
                                        controlCount: sendControlCount,
                                        dataPacketCount: sendDataPacketCount,
                                        jitter: jitter,
                                        latency: latency,
                                        nackCount: sendNackCount,
                                        roundTripTime: roundTripTime)
        
        return (receiveModel, sendModel)
    }
}
