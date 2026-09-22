//
//  SrtCallerInductedState.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 6/15/2024.
//
//  This source file is part of the swift-srt open source project
//
//  Licensed under the MIT License. You may obtain a copy of the License at
//  https://opensource.org/licenses/MIT
//
//  Portions of this project are based on the SRT protocol specification.
//  SRT is licensed under the Mozilla Public License, v. 2.0.
//  You may obtain a copy of the License at
//  https://github.com/Haivision/srt/blob/master/LICENSE
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

struct StrCallerInductedState: SrtCallerState {
    var name: SrtCallerStates = .inducted

    func auto(_ context: SrtCallerContext) {
        
        var extensions = makeExtensions(streamId: context.streamId)
        var encryptionField: UInt16 = 0

        /// A passphrase means we make the stream key and offer it wrapped.
        if let passphrase = context.passphrase {
            do {
                let encryption = try SrtEncryption(passphrase: passphrase)
                context.install(encryption: encryption)
                extensions[.keyMaterialRequest] = encryption.keyMaterial
                encryptionField = encryption.encryptionField
            } catch let error as SrtEncryptionError {
                context.fail(encryption: error)
                context.set(newState: .shutdown)
                return
            } catch {
                context.set(newState: .shutdown)
                return
            }
        }

        let conclusionRequest = SrtHandshake.makeConclusionRequest(
            srtSocketID: context.srtSocketID,
            initialPacketSequenceNumber: context.initialPacketSequenceNumber,
            synCookie: context.synCookie,
            peerIpAddress: context.peerIpAddress,
            extensions: extensions,
            encryptionField: encryptionField
        )

        /// The conclusion request is still addressed to socket 0. The draft reads
        /// as if it should carry the listener's ID from the induction response,
        /// but libsrt's own caller sends 0, and libsrt's listener only routes a
        /// dst-0 handshake to its accept path -- anything else is silently
        /// dropped. The listener's ID is used for everything after the socket
        /// exists.
        let packet = SrtPacket(
            field1: ControlTypes.handshake.asField,
            socketID: 0,
            contents: Data()
        )

        /// The socket is not created here: the connection is not established until
        /// the listener answers with a conclusion response. Advance first so that
        /// response is handled in the right state.
        context.set(newState: .conclusionRequesting)
        context.send(packet, conclusionRequest.data)
        
    }
    
    private func makeExtensions(streamId: String?) -> [HandshakeExtensionTypes: Data] {
        var extensions: [HandshakeExtensionTypes: Data] = [:]

        let hsreq = HandshakeExtensionMessage(
            srtVersion: SrtHandshake.srtLibraryVersion,
            srtFlags: SrtHandshake.defaultSrtFlags,
            receiverTsbpdDelay: SrtHandshake.defaultTsbpdDelay,
            senderTsbpdDelay: SrtHandshake.defaultTsbpdDelay
        )
        extensions[.handshakeRequest] = hsreq.data

        if let streamId, !streamId.isEmpty {
            extensions[.streamId] = Self.encodeStreamId(streamId)
        }

        return extensions
    }

    /// libsrt carries the stream ID as 32-bit words with the bytes reversed inside
    /// each word, zero padded up to a word boundary.
    static func encodeStreamId(_ streamId: String) -> Data {
        guard var bytes = streamId.data(using: .utf8), !bytes.isEmpty else {
            return Data()
        }

        /// SRT_CMD_SID carries at most 512 bytes; truncate rather than trap.
        if bytes.count > 512 {
            bytes = bytes.prefix(512)
        }

        let padding = (4 - (bytes.count % 4)) % 4
        bytes.append(contentsOf: repeatElement(UInt8(0), count: padding))

        var encoded = Data(capacity: bytes.count)
        for start in stride(from: 0, to: bytes.count, by: 4) {
            encoded.append(contentsOf: bytes[start..<(start + 4)].reversed())
        }

        return encoded
    }
    
}
