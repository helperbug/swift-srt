//
//  PidTypes.swift
//
//
//  Created by Ben Waidhofer on 6/19/24.
//

import Foundation

public enum PidTypes: UInt16 {
    case pat = 0     // Program Association Table
    case cat = 1     // Conditional Access Table
    case tsdt = 2    // Transport Stream Description Table
    case ipmp = 3    // IPMP Control Information Table
    case reservedFutureUse = 4
    case dvbMetadataNIT = 16    // Network Information Table
    case dvbMetadataSDT = 17    // Service Description Table
    case dvbMetadataEIT = 18    // Event Information Table
    case dvbMetadataRST = 19    // Running Status Table
    case dvbMetadataTDT = 20    // Time and Date Table
    case networkSynchronization = 21
    case dvbMetadataRNT = 22    // RNT
    case inbandSignalling = 28
    case measurement = 29
    case dit = 30    // Discontinuity Information Table
    case sit = 31    // Selection Information Table
    case programMapTables = 32  // Program Map Tables (starting)
    case digiCipherMGT = 8187   // DigiCipher/ATSC MGT metadata
    case nullPacket = 8191      // Null Packet (used for fixed bandwidth padding)
}
