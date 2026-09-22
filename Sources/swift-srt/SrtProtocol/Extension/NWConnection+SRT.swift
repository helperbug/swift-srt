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
//  An independent implementation of the SRT protocol from the IETF
//  Internet-Draft draft-sharabayko-srt-01, verified against libsrt 1.5.7.
//  No libsrt code is included; see README for licensing and trademark.
//

import Network

extension NWConnection {
    
    func makeUdpHeader(isHost: Bool) -> UdpHeader? {
        
        let serverIp: IPv4Address
        let serverPort: UInt16
        let clientIp: IPv4Address
        let clientPort: UInt16
        let localInterface: String
        let localInterfaceType: String
        
        guard case .hostPort(let caller, let port) = self.endpoint else {
            return nil
        }
        
        guard case .ipv4(let ipv4Address) = caller else {
            return nil
        }
        
        clientIp = ipv4Address
        clientPort = port.rawValue
        
        guard let path = self.currentPath,
              let _ = path.localEndpoint else {
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
        
        let sourceIp: String
        let sourcePort: UInt16
        let destinationIp: String
        let destinationPort: UInt16

        if isHost {
            sourceIp = "\(clientIp)"
            sourcePort = clientPort
            destinationIp = "\(serverIp)"
            destinationPort = serverPort
        } else {
            sourceIp = "\(serverIp)"
            sourcePort = serverPort
            destinationIp = "\(clientIp)"
            destinationPort = clientPort
        }
        
        let udpHeader: UdpHeader = .init(
            sourceIp: sourceIp,
            sourcePort: sourcePort,
            destinationIp: destinationIp,
            destinationPort: destinationPort,
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
