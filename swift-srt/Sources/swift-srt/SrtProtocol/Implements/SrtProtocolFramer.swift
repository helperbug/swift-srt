//
//  SrtProtocolFramer.swift
//  swift-srt
//
//  Created by Ben Waidhofer on 5/25/2024.
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
import Network

class SrtProtocolFramer: NWProtocolFramerImplementation {
    required public init(framer: NWProtocolFramer.Instance) { }
    
    static var label: String = "SrtProtocolFramer"
    static let definition = NWProtocolFramer.Definition(implementation: SrtProtocolFramer.self)
    
    func wakeup(framer: NWProtocolFramer.Instance) { }
    
    func stop(framer: NWProtocolFramer.Instance) -> Bool {
        return true
    }
    
    func cleanup(framer: NWProtocolFramer.Instance) { }
    
    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
        return .ready
    }
    
    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var decodedSrtHeader: SrtPacketHeader? = nil
            var srtPacket: SrtPacket? = nil

            let headerSize = 16
            
            let input = framer.parseInput(minimumIncompleteLength: 0, maximumLength: 2048) {
                (buffer, isComplete) -> Int in
                
                guard let buffer else {
                    return headerSize
                }
                
                let count = buffer.count
                if count < headerSize {
                    return headerSize
                }
                
                // Convert UnsafeMutableRawBufferPointer to UnsafeRawBufferPointer
                let rawBuffer = UnsafeRawBufferPointer(buffer)
                decodedSrtHeader = SrtPacketHeader(rawBuffer)
                srtPacket = .init(data: Data(rawBuffer))
                return headerSize
            }
            
            guard input,
                  let srtPacket = srtPacket,
                  let srtHeader = decodedSrtHeader else {
                return headerSize
            }
            
            let message = NWProtocolFramer.Message(srtPacket: srtPacket)
            let bodyLength = srtHeader.contentLength
            
            if !framer.deliverInputNoCopy(length: bodyLength, message: message, isComplete: true) {
                return headerSize
            }
        }
    }
    
    func handleOutput(framer: NWProtocolFramer.Instance,
                      message: NWProtocolFramer.Message,
                      messageLength: Int,
                      isComplete: Bool) {

        guard let srtPacket = message.srtPacket else {
            return
        }

        framer.writeOutput(data: srtPacket.data)
        
        do {

            try framer.writeOutputNoCopy(length: messageLength)

        } catch {

            print("Error writing output no copy: \(error)")

        }
    }
}
