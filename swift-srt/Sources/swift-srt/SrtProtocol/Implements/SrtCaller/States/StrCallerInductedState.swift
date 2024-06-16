//
//  File.swift
//  
//
//  Created by Ben Waidhofer on 6/15/24.
//

import Foundation

struct StrCallerInductedState: SrtCallerState {
    var name: SrtCallerStates = .inducted

    func auto(_ context: SrtCallerContext) {
        
        let extensions = makeExtensions(streamId: "input/live/test")
        
        let conclusionRequest = SrtHandshake.makeConclusionRequest(srtSocketID: context.srtSocketID,
                                                                   initialPacketSequenceNumber: context.initialPacketSequenceNumber,
                                                                   synCookie: context.synCookie,
                                                                   peerIpAddress: context.peerIpAddress,
                                                                   extensions: extensions)
        
        let packet = SrtPacket(field1: ControlTypes.handshake.asField, socketID: 0, contents: Data())
        let contents = conclusionRequest.makePacket(socketId: context.srtSocketID).contents
        
        context.send(packet, contents)

        let socket = SrtSocketContext(encrypted: context.encrypted,
                                      socketId: context.srtSocketID,
                                      synCookie: context.synCookie)

        context.onSocketCreated(socket)

        context.set(newState: .conclusionRequesting)
        
    }
    
    private func makeExtensions(streamId: String? = nil) -> [HandshakeExtensionTypes: Data] {
        var extensions: [HandshakeExtensionTypes: Data] = [:]

        let hsreqExtension = createHsreqExtension(
            srtVersion: 0x010502,
            srtFlags: 0xbf,
            receiverTsbpdDelay: 120,
            senderTsbpdDelay: 0
        )
        extensions[.handshakeRequest] = hsreqExtension

        if let streamId {
            let cmdStdExtension = createCmdStdExtension(streamId: streamId)
            extensions[.streamId] = cmdStdExtension
        }

        return extensions
    }
    
    private func createHsreqExtension(
        srtVersion: UInt32,
        srtFlags: UInt32,
        receiverTsbpdDelay: UInt16,
        senderTsbpdDelay: UInt16
    ) -> Data {
        var hsreqExtension = Data()
        let extensionType = HandshakeExtensionTypes.handshakeRequest.rawValue
        let extensionLength = UInt16(3)

        hsreqExtension.append(contentsOf: extensionType.bytes)
        hsreqExtension.append(contentsOf: extensionLength.bytes)
        hsreqExtension.append(contentsOf: srtVersion.bytes)
        hsreqExtension.append(contentsOf: srtFlags.bytes)
        hsreqExtension.append(contentsOf: receiverTsbpdDelay.bytes)
        hsreqExtension.append(contentsOf: senderTsbpdDelay.bytes)
        
        return hsreqExtension
    }

    private func createCmdStdExtension(streamId: String) -> Data {
        guard let streamIdData = streamId.data(using: .utf8), streamIdData.count <= 512 else {
            fatalError("Stream ID is too long")
        }

        var paddedStreamIdData = streamIdData
        let paddingLength = (4 - (streamIdData.count % 4)) % 4
        if paddingLength > 0 {
            paddedStreamIdData.append(contentsOf: repeatElement(UInt8(0), count: paddingLength))
        }
        
        var cmdStdExtension = Data()
        let extensionType = HandshakeExtensionTypes.streamId.rawValue
        let extensionLength = UInt16(paddedStreamIdData.count / 4) // Extension length in 4-byte words
        
        cmdStdExtension.append(contentsOf: extensionType.littleEndian.bytes)
        cmdStdExtension.append(contentsOf: extensionLength.littleEndian.bytes)

        for chunk in stride(from: 0, to: paddedStreamIdData.count, by: 4) {
            let word = paddedStreamIdData[chunk..<chunk+4]
            let littleEndianWord = word.reversed()
            cmdStdExtension.append(contentsOf: littleEndianWord)
        }
        
        return cmdStdExtension
    }
    
}
