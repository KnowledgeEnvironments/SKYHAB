// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct SkyHABiOSApp: App {
    @StateObject private var model = DashboardModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            IOSDashboardView().environmentObject(model).preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            // The 5 s authoritative tick is pointless while backgrounded; keep the
            // connection and state for foreground return.
            if phase == .active { model.resumePolling() } else { model.suspendPolling() }
        }
    }
}
