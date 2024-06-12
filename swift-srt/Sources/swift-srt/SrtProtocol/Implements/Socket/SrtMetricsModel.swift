//
//  SrtMetricsModel.swift
//
//
//  Created by Ben Waidhofer on 6/9/24.
//

import Foundation

public struct SrtMetricsModel: Identifiable {
    
    public let id: UUID = .init()
    public let ackAckCount: Int
    public let ackCount: Int
    public let bytesCount: Int
    public let controlCount: Int
    public let dataPacketCount: Int
    public let jitter: Double
    public let latency: Double
    public let nackCount: Int
    public let roundTripTime: Double
    
    init(
        ackAckCount: Int = 0,
        ackCount: Int = 0,
        bytesCount: Int = 0,
        controlCount: Int = 0,
        dataPacketCount: Int = 0,
        jitter: Double = 0.0,
        latency: Double = 0.0,
        nackCount: Int = 0,
        roundTripTime: Double = 0.0
    ) {
        self.ackAckCount = ackAckCount
        self.ackCount = ackCount
        self.bytesCount = bytesCount
        self.controlCount = controlCount
        self.dataPacketCount = dataPacketCount
        self.jitter = jitter
        self.latency = latency
        self.nackCount = nackCount
        self.roundTripTime = roundTripTime
    }
    
    public static var blank: SrtMetricsModel {
        .init(
            ackAckCount: 0,
            ackCount: 0,
            bytesCount: 0,
            controlCount: 0,
            dataPacketCount: 0,
            jitter: 0.0,
            latency: 0.0,
            nackCount: 0,
            roundTripTime: 0.0
        )
    }
}
