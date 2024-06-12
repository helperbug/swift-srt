//
//  File.swift
//
//
//  Created by Ben Waidhofer on 6/12/24.
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
