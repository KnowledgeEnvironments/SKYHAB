// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI

@main
struct SkyHABApp: App {
    @StateObject private var model = DashboardModel()
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup("skyHAB") {
            DashboardView().environmentObject(model).frame(minWidth: 620, minHeight: 520)
                .preferredColorScheme(.dark).tint(SkyTheme.amber)
                .sheet(isPresented: $showAbout) { AboutSkyHABView().environmentObject(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About skyHAB") { showAbout = true }
            }
        }
        MenuBarExtra("skyHAB", systemImage: model.unreachable == 0 ? "house.fill" : "house.and.flag.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.connected ? "skyHAB online" : "skyHAB disconnected").font(.headline)
                Text("\(model.resources.count) resources · \(model.unreachable) unreachable")
                Divider()
                Button("Refresh") { Task { await model.refresh() } }
                Button("Open skyHAB") { NSApp.activate(ignoringOtherApps: true) }
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            }.padding()
        }
    }
}

struct AboutSkyHABView: View {
    @EnvironmentObject var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0" }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 92, height: 92)
            Text("skyHAB").font(.largeTitle.bold())
            Text("sky Habitat Automation Builder").font(.callout).foregroundStyle(.secondary)
            Text("Version \(appVersion)").font(.caption.monospaced()).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 5) {
                Text("Server: \(model.serverEndpoint)").font(.body.monospaced())
                Text(model.serverIdentity).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Text("(C) if <src@lispm.net>").font(.callout)
            Text(model.siteName).font(.callout)
            Text(model.siteSubtitle).font(.callout).foregroundStyle(.secondary)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).padding(.top, 4)
        }
        .padding(28).frame(width: 430)
        .background(SkyTheme.background)
    }
}
