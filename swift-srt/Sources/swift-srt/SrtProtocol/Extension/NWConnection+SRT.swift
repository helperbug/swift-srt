//
//  NWConnection+SRT.swift
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

import Network

extension NWConnection {
    
    func makeUdpHeader() -> UdpHeader? {
        
        let serverIp: IPv4Address
        let serverPort: UInt16
        let clientIp: IPv4Address
        let clientPort: UInt16
        let localInterface: String
        let localInterfaceType: String

        guard case .hostPort(let caller, let port) = self.endpoint else {
            return nil
        }
        
        guard let host = caller as? NWEndpoint.Host else {
            return nil
        }
        
        guard case .ipv4(let ipv4Address) = host else {
            return nil
        }
        
        clientIp = ipv4Address
        clientPort = port.rawValue
        
        guard let path = self.currentPath,
              let localEndpoint = path.localEndpoint else {
            return nil
        }
        
        if let localPath = self.currentPath,
           let localEndpoint = localPath.localEndpoint,
           case let .hostPort(localHost, localPort) = localEndpoint,
           case .ipv4(let localIpV4Address) = localHost {
            
            serverIp = localIpV4Address
            serverPort = localPort.rawValue
            
            if let interface = localPath.availableInterfaces.first {
                
                localInterface = "\(interface)"
                localInterfaceType = "\(interface.type)"

            } else {
                localInterface = "-"
                localInterfaceType = "-"
            }
            
        } else {
            return nil
        }
        
        let udpHeader: UdpHeader = .init(
            sourceIp: "\(clientIp)",
            sourcePort: clientPort,
            destinationIp: "\(serverIp)",
            destinationPort: serverPort,
            interface: localInterface,
            interfaceType: localInterfaceType
        )
     
        return udpHeader
        
    }
    
}

/*
 if let path = connection.currentPath {
     if let localEndpoint = path.localEndpoint {
         
         if case let .hostPort(host, port) = localEndpoint {
             print("\(host):\(port)")
         }
         
         print("\(localEndpoint)")
     }
     path.availableInterfaces.forEach { interface in
         
         print("\(interface.index)")
         print("\(interface)")

     }
 }
 */
