//
//  NetworkMonitor.swift
//  
//
//  Created by Alisa Mylnikova on 01.09.2023.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkMonitor {
    var isConnected = false

    func monitorConnectivity() async {
        let monitor = NWPathMonitor()
        await withTaskCancellationHandler {
            for await path in monitor {
                guard !Task.isCancelled else { return }
                isConnected = path.status == .satisfied
            }
        } onCancel: {
            monitor.cancel()
        }
    }
}
