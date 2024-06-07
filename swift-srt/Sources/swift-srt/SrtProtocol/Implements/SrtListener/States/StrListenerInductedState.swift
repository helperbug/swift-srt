//
//  StrListenerInductedState.swift
//
//
//  Created by Ben Waidhofer on 6/7/24.
//

import Foundation

struct StrListenerInductedState: SrtListenerState {
    
    let name: SrtListenerStates = .inducted
    
    func auto(_ context: SrtListenerContext) {
        
        let conclusionResponse = makeConclusionResponse(srtSocketID: context.srtSocketID,
                                                        initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                                                        synCookie: context.synCookie,
                                                        peerIpAddress: context.peerIpAddress)
        
        let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: context.srtSocketID, contents: Data())
        let contents = conclusionResponse.makePacket(socketId: context.srtSocketID).contents
        
        context.send(packet, contents)
        context.set(newState: .active)
        
    }
    
    private func makeConclusionResponse(
        srtSocketID: UInt32,
        initialPacketSequenceNumber: UInt32,
        synCookie: UInt32,
        peerIpAddress: Data
    ) -> SrtHandshake {
        
        let handshakeExt = HandshakeExtensionMessage(srtVersion: 0x00010502,
                                                     srtFlags: 0xbf,
                                                     receiverTsbpdDelay: 120,
                                                     senderTsbpdDelay: 120)
        
        let contents = handshakeExt.data
        
        return SrtHandshake(
            hsVersion: .version5,
            encryptionField: 0, // No encryption
            extensionField: 1,
            initialPacketSequenceNumber: initialPacketSequenceNumber,
            maximumTransmissionUnitSize: 1500,
            maximumFlowWindowSize: 8192,
            handshakeType: .conclusion,
            srtSocketID: srtSocketID,
            synCookie: synCookie,
            peerIPAddress: peerIpAddress,
            extensionType: .handshakeResponse,
            extensionLength: UInt16(contents.count / 4),
            extensionContents: contents
        )
    }

}
