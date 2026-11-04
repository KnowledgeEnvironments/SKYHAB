// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI
import Charts
import UIKit
import PhotosUI

private enum IOSTheme {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.050)
    static let panel = Color(red: 0.045, green: 0.105, blue: 0.115)
    static let face = Color(red: 0.075, green: 0.175, blue: 0.185)
    static let inset = Color(red: 0.008, green: 0.022, blue: 0.026)
    static let cyan = Color(red: 0.20, green: 0.90, blue: 0.88)
    static let amber = Color(red: 1.0, green: 0.58, blue: 0.13)
    static let phosphor = Color(red: 0.42, green: 1.0, blue: 0.48)
    static let shadow = Color.black.opacity(0.82)
    static let highlight = Color.white.opacity(0.28)
}

private extension View {
    func iosVintagePanel(_ fill: Color = IOSTheme.panel) -> some View {
        background(fill)
            .overlay(alignment: .top) { Rectangle().fill(IOSTheme.highlight).frame(height: 1) }
            .overlay(alignment: .leading) { Rectangle().fill(IOSTheme.highlight.opacity(0.65)).frame(width: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(IOSTheme.shadow).frame(height: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(IOSTheme.shadow).frame(width: 2) }
    }

    // Vintage panel whose light edge follows a rounded border. Used for floating
    // cards that sit near the screen's own corner radius so the chrome is not
    // square-clipped by the display curvature.
    func iosVintageRoundedPanel(_ fill: Color = IOSTheme.panel, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(IOSTheme.highlight.opacity(0.9), lineWidth: 1))
            .shadow(color: IOSTheme.shadow, radius: 0, x: 1, y: 1)
    }

    // Rounded top edge only: the card echoes the display curvature where it meets
    // the top of the screen and keeps the square bottom edge of the instrument
    // language. The light edge stroke follows the curve.
    func iosVintageTopRoundedPanel(_ fill: Color, radius: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
        return background(fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(IOSTheme.highlight.opacity(0.9), lineWidth: 1))
            .shadow(color: IOSTheme.shadow, radius: 0, x: 1, y: 1)
    }

    func iosNetworkChassis() -> some View {
        background(IOSTheme.panel)
            .overlay(Rectangle().stroke(IOSTheme.inset, lineWidth: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.9)).frame(height: 3) }
            .overlay(alignment: .trailing) { Rectangle().fill(Color.black.opacity(0.72)).frame(width: 3) }
    }
}

// Shared horizontal inset so floating headers and the scrolling content column
// are cut from one constant and can never drift out of alignment.
private let kIOSContentInset: CGFloat = 12

// Corner radius of the Duo's cover display is 59 px @3x (~20 pt). The floating
// headers use a steeper, larger top curve than that so the bend reads clearly;
// x/y stay equivalent (continuous circular arc, top corners only).
private let kIOSHeaderTopCornerRadius: CGFloat = 28

// The unfolded Duo canvas is 669 pt wide; the folded cover is 466 pt. Above this
// threshold the shell switches to dual-column layouts.
private let kIOSWideLayoutThreshold: CGFloat = 560

// Width of the persistent module rail in the unfolded master-detail shell.
private let kIOSRailWidth: CGFloat = 240

private func iosIsWide(_ width: CGFloat) -> Bool {
    width >= kIOSWideLayoutThreshold || ProcessInfo.processInfo.environment["SKYHAB_FORCE_WIDE"] == "1"
}

// Reports the enclosing container width to a binding so views can switch between
// the folded single column and unfolded dual-column layouts on live fold/unfold.
private struct IOSWidthReader: View {
    @Binding var width: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        }
    }
}

private struct IOSVintagePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(alignment: .top) { Rectangle().fill(configuration.isPressed ? IOSTheme.shadow : .clear).frame(height: 2) }
            .overlay(alignment: .leading) { Rectangle().fill(configuration.isPressed ? IOSTheme.shadow : .clear).frame(width: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(configuration.isPressed ? IOSTheme.highlight : .clear).frame(height: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(configuration.isPressed ? IOSTheme.highlight : .clear).frame(width: 2) }
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

private struct IOSGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0.0, through: size.width, by: 24).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0.0, through: size.height, by: 24).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(path, with: .color(IOSTheme.cyan.opacity(0.035)), lineWidth: 0.5)
        }
        .background(IOSTheme.background).ignoresSafeArea()
    }
}

struct IOSDashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @AppStorage("skyhab.ios.host") private var host = "127.0.0.1"
    @AppStorage("skyhab.ios.port") private var port = 3636
    @AppStorage("skyhab.ios.client") private var clientName = "skyHAB.ios"
    @AppStorage("skyhab.ios.token") private var token = ""
    @State private var showingSettings = false
    @State private var navigationPath: [String] = []
    @State private var contentWidth: CGFloat = 0
    private var isWide: Bool { iosIsWide(contentWidth) }

    var body: some View {
        Group {
            if isWide { wideBody } else { foldedBody }
        }
        .background(IOSWidthReader(width: $contentWidth))
        .tint(IOSTheme.cyan)
        .task {
            await reconnect()
            if let previewSection = ProcessInfo.processInfo.environment["SKYHAB_START_SECTION"],
               model.views.contains(where: { $0.id == previewSection }) {
                navigationPath = [previewSection]
            }
            await model.run()
        }
        .sheet(isPresented: $showingSettings) {
            IOSSettingsView(host: $host, port: $port, clientName: $clientName, token: $token) { Task { await reconnect() } }
                .preferredColorScheme(.dark)
        }
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(IOSTheme.cyan)
                .frame(width: 34, height: 26).iosVintagePanel(IOSTheme.face)
        }
        .buttonStyle(.plain).padding(12)
    }

    // Unfolded: a persistent module rail beside the selected submodule's console,
    // so navigation between modules never loses the canvas to push/pop.
    private var wideBody: some View {
        HStack(alignment: .top, spacing: kIOSContentInset) {
            ScrollView {
                LazyVStack(spacing: 9) {
                    IOSConsoleHeader(title: "skyHAB", subtitle: model.siteName, online: model.connected)
                    ForEach(model.views) { view in
                        Button {
                            navigationPath = [view.id]
                        } label: {
                            IOSCategoryRow(view: view, count: resourceCount(for: view.id), selected: navigationPath.first == view.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(kIOSContentInset)
            }
            .frame(width: kIOSRailWidth)
            ZStack {
                IOSGrid()
                if let selected = navigationPath.first, model.views.contains(where: { $0.id == selected }) {
                    IOSSectionView(section: selected, title: model.views.first { $0.id == selected }?.title ?? selected, embedded: true)
                        .id(selected)
                } else {
                    IOSGrid().overlay(
                        Text("Select a module").font(.caption.monospaced()).foregroundStyle(.secondary)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) { settingsButton }
    }

    private var foldedBody: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                IOSGrid()
                ScrollView {
                    LazyVStack(spacing: 9) {
                        IOSConsoleHeader(title: "skyHAB", subtitle: model.siteName, online: model.connected)
                        if !model.error.isEmpty {
                            Text(model.error).font(.caption.monospaced()).foregroundStyle(IOSTheme.amber)
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading).iosVintagePanel(IOSTheme.inset)
                        }
                        ForEach(model.views) { view in
                            NavigationLink(value: view.id) {
                                IOSCategoryRow(view: view, count: resourceCount(for: view.id))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(kIOSContentInset)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { section in
                IOSSectionView(section: section, title: model.views.first { $0.id == section }?.title ?? section)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) { settingsButton }
        }
    }

    private func resourceCount(for section: String) -> Int {
        resources(in: section, query: "").count
    }
    private func resources(in section: String, query: String) -> [SkyResource] {
        filteredResources(model.resources, section: section, query: query)
    }
    private func reconnect() async {
        if let bundledToken = KeychainToken.load(), !bundledToken.isEmpty { token = bundledToken }
        let bundled = SkyClientConfiguration.load()
        if host.isEmpty { host = bundled.host }
        if port == 0 { port = Int(bundled.port) }
        if clientName.isEmpty { clientName = bundled.client }
        let environment = ProcessInfo.processInfo.environment
        let resolvedToken = token.isEmpty ? environment["SKYHAB_TOKEN"] ?? environment["SKYLAB_TOKEN"] ?? "" : token
        model.configure(host: host, port: UInt16(clamping: port), token: resolvedToken, clientName: clientName)
        await model.refresh()
    }
}

private struct IOSHomeCard<Content: View>: View {
    let title: String; let subtitle: String; let destination: String; @ViewBuilder let content: Content
    var body: some View { NavigationLink(value: destination) { VStack(alignment: .leading, spacing: 8) { HStack { VStack(alignment: .leading, spacing: 1) { Text(title).font(.headline); Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(IOSTheme.cyan) }; content }.padding(11).frame(maxWidth: .infinity, alignment: .leading).iosVintagePanel() }.buttonStyle(IOSVintagePressStyle()) }
}

private struct IOSHomeMetrics: View {
    let values: [(String, String)]
    var body: some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) { ForEach(values.indices, id: \.self) { index in HStack(spacing: 3) { Text(values[index].0).foregroundStyle(.secondary).lineLimit(1); Spacer(); Text(values[index].1).monospacedDigit().lineLimit(1) }.font(.system(size: 8)).padding(6).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.15), lineWidth: 1)) } } }
}

private struct IOSConsoleHeader: View {
    let title: String
    let subtitle: String
    let online: Bool
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(IOSTheme.amber).frame(width: 5, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                    // "Offline" is wider than "Online"; keep the title on one line
                    // and let the spacer absorb the difference instead.
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Text(subtitle).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    // Take all remaining width so the address scales to fit the rail
                    // column instead of truncating long site names.
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Circle().fill(online ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 9, height: 9)
            Text(online ? "Online" : "Offline").font(.caption.monospaced().bold())
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .padding(13).iosVintageTopRoundedPanel(IOSTheme.face, radius: kIOSHeaderTopCornerRadius)
    }
}

private struct IOSCategoryRow: View {
    let view: SkyViewSummary
    let count: Int
    var selected: Bool = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon(view.id)).foregroundStyle(IOSTheme.cyan).frame(width: 24)
            Text(view.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Text("\(count)").font(.caption.monospaced()).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(IOSTheme.cyan)
        }
        .padding(.horizontal, 13).frame(height: 48)
        .iosVintagePanel(selected ? IOSTheme.face : IOSTheme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(selected ? IOSTheme.cyan : .clear).frame(width: 3) }
    }
}

private struct IOSSectionView: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    let section: String
    let title: String
    // Embedded mode renders inside the unfolded master-detail pane: no back
    // button, since the module rail owns navigation there.
    var embedded: Bool = false
    @State private var search = ""
    @State private var lightingRoom = ""
    private var rooms: [String] { Array(Set(model.resources.filter { $0.presentation_home == "lighting" && !$0.room.isEmpty }.map(\.room))).sorted() }

    // One presentation section's folder tab and its panels, shared by the folded
    // single column and the unfolded dual-column layout.
    @ViewBuilder
    private func sectionBlock(_ definition: SkyPresentationSection, _ raw: [SkyResource]) -> some View {
        let resources = raw.filter { lightingRoom.isEmpty || $0.room == lightingRoom }
        IOSFolderTab(title: definition.title)
        if section == "energy" && definition.id == "flow" {
            if let projection = model.energyFlowProjection() { IOSPowerFlowPanel(projection: projection) }
            IOSPowerInstruments(points: model.energyHistory)
        } else if section == "energy" && definition.id == "protection", let projection = model.upsProjection() {
            IOSUPSPanel(projection: projection)
        } else if section == "habitat" && definition.id == "daylight", let ephemeris = resources.first {
            IOSDaylightPanel(resource: ephemeris, state: model.displayStatesByResource[ephemeris.id] ?? [])
        } else if section == "habitat" && definition.id == "air-quality", let purifier = resources.first {
            IOSAirQualityPanel(resource: purifier, state: model.displayStatesByResource[purifier.id] ?? [], history: model.airQualityHistory)
        } else if resources.isEmpty {
            Text("No matching systems").font(.caption.monospaced()).foregroundStyle(.secondary).padding(.vertical, 12)
        } else {
            ForEach(resources) { resource in
                if section == "security" && resource.class == "alarm-panel" {
                    IOSAlarmPanel(resource: resource, state: model.displayStatesByResource[resource.id] ?? [])
                } else {
                    IOSResourceCard(resource: resource, state: model.displayStatesByResource[resource.id] ?? [])
                        .padding(.leading, section == "compute" ? min(CGFloat(resource.depth) * 12, 30) : 0)
                }
            }
        }
    }
    var body: some View {
        ZStack {
            IOSGrid()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if !embedded {
                        Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 32, height: 28).iosVintagePanel(IOSTheme.face) }.buttonStyle(.plain)
                    }
                    Text(title).font(.system(size: 19, weight: .bold, design: .rounded))
                    Spacer()
                    Circle().fill(model.connected ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
                }
                // Float the header as an inset card like the home screen. A full-bleed
                // band here ran edge-to-edge into the cover display's sensor cutout;
                // the rounded top edge echoes the display curvature instead of being
                // square-clipped by it, while the bottom edge stays square.
                .padding(12).iosVintageTopRoundedPanel(IOSTheme.face, radius: kIOSHeaderTopCornerRadius)
                .padding(.horizontal, kIOSContentInset).padding(.top, kIOSContentInset)
                TextField("Search", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.callout.monospaced()).padding(.horizontal, 11).frame(height: 34)
                    .background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.35), lineWidth: 1))
                    .padding(.horizontal, kIOSContentInset).padding(.vertical, 10)
                    .background(IOSTheme.background)
                if section == "lighting" {
                    Menu {
                        Button("All Rooms") { lightingRoom = "" }
                        ForEach(rooms, id: \.self) { room in Button(room) { lightingRoom = room } }
                    } label: {
                        HStack { Text("Room").foregroundStyle(.secondary); Spacer(); Text(lightingRoom.isEmpty ? "All Rooms" : lightingRoom); Image(systemName: "chevron.down") }
                            .font(.caption.monospaced().bold()).padding(.horizontal, 11).frame(height: 34).iosVintagePanel(IOSTheme.face)
                    }.padding(.horizontal, kIOSContentInset).padding(.bottom, 10)
                }
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if section == "storage" {
                            IOSFolderTab(title: model.presentationViews["storage"]?.sections.first?.title ?? "Storage")
                            IOSStorageView(query: search)
                        } else if section == "overview" {
                            IOSSiteOverview(query: search)
                        } else if section == "network" {
                            IOSNetworkView(query: search)
                        } else {
                            let sections = model.presentationSections(for: section, query: search)
                            ForEach(sections.indices, id: \.self) { index in
                                sectionBlock(sections[index].0, sections[index].1)
                            }
                        }
                    }.padding(kIOSContentInset)
                }
                .refreshable { await model.refresh() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct IOSDaylightPanel: View {
    let resource: SkyResource
    let state: [StateRow]
    private func text(_ metric: String) -> String { state.first { $0.metric == metric }?.display ?? "—" }
    private func fraction(_ metric: String) -> Double { state.first { $0.metric == metric }.flatMap { if case .number(let value) = $0.value { value / 100 } else { nil } } ?? 0 }
    private var daylight: Bool { state.first { $0.metric == "daylight" }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(resource.pretty_name).font(.headline)
                    Text(text("site_address")).font(.caption2).foregroundStyle(.secondary)
                    Text(text("site_coordinates")).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary)
                    Text(text("next_transition")).font(.caption2.monospaced().bold()).foregroundStyle(daylight ? IOSTheme.amber : IOSTheme.cyan)
                }
                Spacer()
                Text(text("solar_phase")).font(.caption.monospaced()).foregroundStyle(daylight ? IOSTheme.amber : IOSTheme.cyan)
            }
            IOSDaylightWave(
                dawn: fraction("sunrise_day_progress"), dusk: fraction("sunset_day_progress"), now: fraction("day_progress"), daylight: daylight,
                morning: [fraction("astronomical_dawn_day_progress"), fraction("nautical_dawn_day_progress"), fraction("civil_dawn_day_progress"), fraction("sunrise_day_progress")],
                evening: [fraction("sunset_day_progress"), fraction("civil_dusk_day_progress"), fraction("nautical_dusk_day_progress"), fraction("astronomical_dusk_day_progress")]
            )
            VStack(spacing: 3) {
                HStack { Text("Threshold"); Spacer(); Text("Dawn").frame(width: 70, alignment: .trailing); Text("Dusk").frame(width: 70, alignment: .trailing) }.foregroundStyle(.secondary)
                ForEach([("Sun", "sunrise", "sunset", IOSTheme.amber), ("Civil · −6°", "civil_dawn", "civil_dusk", IOSTheme.amber.opacity(0.72)), ("Nautical · −12°", "nautical_dawn", "nautical_dusk", IOSTheme.cyan), ("Astronomical · −18°", "astronomical_dawn", "astronomical_dusk", IOSTheme.cyan.opacity(0.55))], id: \.0) { label, dawnMetric, duskMetric, color in
                    HStack(spacing: 5) { Rectangle().fill(color).frame(width: 10, height: 4); Text(label); Spacer(); Text(text(dawnMetric)).frame(width: 70, alignment: .trailing); Text(text(duskMetric)).frame(width: 70, alignment: .trailing) }
                }
            }.font(.system(size: 8, design: .monospaced)).padding(7).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
        }.padding(12).iosVintagePanel()
    }
}

private struct IOSDaylightWave: View {
    let dawn: Double
    let dusk: Double
    let now: Double
    let daylight: Bool
    let morning: [Double]
    let evening: [Double]
    var body: some View {
        Canvas { context, size in
            let left = 12.0, right = size.width - 12, width = right - left
            let horizon = size.height * 0.48, amplitude = size.height * 0.29
            func x(_ fraction: Double) -> Double { left + min(max(fraction, 0), 1) * width }
            func dayY(_ fraction: Double) -> Double { horizon - sin(.pi * (fraction - dawn) / max(0.001, dusk - dawn)) * amplitude }
            let nightLength = max(0.001, 1 - dusk + dawn)
            func nightY(_ fraction: Double) -> Double {
                let phase = fraction >= dusk ? (fraction - dusk) / nightLength : (1 - dusk + fraction) / nightLength
                return horizon + sin(.pi * phase) * amplitude
            }
            let morningColors = [IOSTheme.cyan.opacity(0.05), IOSTheme.cyan.opacity(0.10), IOSTheme.amber.opacity(0.12)]
            let eveningColors = [IOSTheme.amber.opacity(0.12), IOSTheme.cyan.opacity(0.10), IOSTheme.cyan.opacity(0.05)]
            if morning.count == 4 && evening.count == 4 {
                for index in 0..<3 {
                    var band = Path(); band.addRect(CGRect(x: x(morning[index]), y: 8, width: max(0, x(morning[index + 1]) - x(morning[index])), height: size.height - 28)); context.fill(band, with: .color(morningColors[index]))
                    var eveningBand = Path(); eveningBand.addRect(CGRect(x: x(evening[index]), y: 8, width: max(0, x(evening[index + 1]) - x(evening[index])), height: size.height - 28)); context.fill(eveningBand, with: .color(eveningColors[index]))
                }
            }
            for hour in stride(from: 0, through: 24, by: 3) {
                let position = Double(hour) / 24
                var grid = Path(); grid.move(to: CGPoint(x: x(position), y: 8)); grid.addLine(to: CGPoint(x: x(position), y: size.height - 20))
                context.stroke(grid, with: .color(IOSTheme.cyan.opacity(hour % 6 == 0 ? 0.22 : 0.09)), lineWidth: hour % 6 == 0 ? 0.8 : 0.5)
                if hour % 6 == 0 { context.draw(Text(String(format: "%02d", hour)).font(.system(size: 7, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: x(position), y: size.height - 9)) }
            }
            var dayFill = Path(); dayFill.move(to: CGPoint(x: x(dawn), y: horizon))
            for step in 0...64 { let value = dawn + (dusk - dawn) * Double(step) / 64; dayFill.addLine(to: CGPoint(x: x(value), y: dayY(value))) }
            dayFill.addLine(to: CGPoint(x: x(dusk), y: horizon)); dayFill.closeSubpath(); context.fill(dayFill, with: .color(IOSTheme.amber.opacity(0.22)))
            var dayLine = Path(); for step in 0...64 { let value = dawn + (dusk - dawn) * Double(step) / 64; let point = CGPoint(x: x(value), y: dayY(value)); step == 0 ? dayLine.move(to: point) : dayLine.addLine(to: point) }
            context.stroke(dayLine, with: .color(IOSTheme.amber), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            func drawNight(_ start: Double, _ end: Double) {
                var fill = Path(); fill.move(to: CGPoint(x: x(start), y: horizon))
                for step in 0...32 { let value = start + (end - start) * Double(step) / 32; fill.addLine(to: CGPoint(x: x(value), y: nightY(value))) }
                fill.addLine(to: CGPoint(x: x(end), y: horizon)); fill.closeSubpath(); context.fill(fill, with: .color(IOSTheme.cyan.opacity(0.12)))
                var line = Path(); for step in 0...32 { let value = start + (end - start) * Double(step) / 32; let point = CGPoint(x: x(value), y: nightY(value)); step == 0 ? line.move(to: point) : line.addLine(to: point) }
                context.stroke(line, with: .color(IOSTheme.cyan.opacity(0.72)), lineWidth: 1.4)
            }
            drawNight(0, dawn); drawNight(dusk, 1)
            var horizonLine = Path(); horizonLine.move(to: CGPoint(x: left, y: horizon)); horizonLine.addLine(to: CGPoint(x: right, y: horizon)); context.stroke(horizonLine, with: .color(IOSTheme.highlight.opacity(0.5)), lineWidth: 1)
            for (boundary, label) in [(dawn, "RISE"), (dusk, "SET")] {
                var marker = Path(); marker.addEllipse(in: CGRect(x: x(boundary) - 3, y: horizon - 3, width: 6, height: 6)); context.fill(marker, with: .color(IOSTheme.amber))
                context.draw(Text(label).font(.system(size: 6, weight: .bold, design: .monospaced)).foregroundColor(IOSTheme.amber), at: CGPoint(x: x(boundary), y: horizon - 10))
            }
            let currentY = daylight ? dayY(now) : nightY(now)
            var needle = Path(); needle.move(to: CGPoint(x: x(now), y: 7)); needle.addLine(to: CGPoint(x: x(now), y: size.height - 20)); context.stroke(needle, with: .color(daylight ? IOSTheme.amber : IOSTheme.cyan), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            var current = Path(); current.addEllipse(in: CGRect(x: x(now) - 4, y: currentY - 4, width: 8, height: 8)); context.fill(current, with: .color(daylight ? IOSTheme.amber : IOSTheme.cyan))
        }
        .frame(height: 132).background(IOSTheme.inset)
        .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
    }
}

private struct IOSAirQualityPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    let history: [EnergyChartPoint]
    var summaryOnly = false
    private let metrics = ["temperature", "humidity", "pm2_5", "pm10", "voc_index", "no2_index", "formaldehyde"]
    private func row(_ metric: String) -> StateRow? { state.first { $0.metric == metric } }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "air.purifier.fill").foregroundStyle(IOSTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summaryOnly ? "Air Quality" : resource.pretty_name).font(.headline)
                    Text(summaryOnly ? "site environmental history" : [state.first(where: { $0.metric == "power" })?.display, state.first(where: { $0.metric == "fan_state" })?.display].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                ForEach(metrics, id: \.self) { metric in
                    if let value = row(metric) {
                        HStack(spacing: 4) {
                            Text(value.label ?? metric).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 3)
                            Text(value.display).monospacedDigit().lineLimit(1)
                        }.font(.system(size: 9)).padding(7).background(IOSTheme.inset)
                            .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
                    }
                }
            }
            IOSAirQualityTrends(points: history)
            if !summaryOnly { IOSDysonControls(resource: resource, state: state) }
        }.padding(12).iosVintagePanel()
    }
}

private struct IOSAirQualityTrends: View {
    let points: [EnergyChartPoint]
    private let instruments: [(title: String, series: [String], unit: String)] = [
        ("Particles", ["PM2.5", "PM10", "Formaldehyde"], "µg/m³"),
        ("Air Quality Indices", ["VOC", "NO₂"], "index")
    ]
    private func color(_ series: String) -> Color {
        switch series {
        case "PM2.5", "VOC": return IOSTheme.cyan
        case "PM10", "NO₂": return IOSTheme.amber
        default: return IOSTheme.phosphor
        }
    }
    var body: some View {
        VStack(spacing: 7) {
            ForEach(instruments, id: \.title) { instrument in
                let values = points.filter { instrument.series.contains($0.series) }
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(instrument.title).font(.caption.monospaced().bold())
                        Spacer()
                        Text("24 h").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    if values.isEmpty {
                        HStack { Spacer(); Text("Collecting history").font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer() }
                            .frame(height: 78).background(IOSTheme.inset)
                    } else {
                        Chart {
                            ForEach(instrument.series, id: \.self) { series in
                                ForEach(values.filter { $0.series == series }) { point in
                                    LineMark(x: .value("Time", point.date), y: .value(instrument.unit, point.value))
                                        .foregroundStyle(by: .value("Series", series)).lineStyle(.init(lineWidth: 1.6))
                                }
                            }
                        }
                        .chartForegroundStyleScale(
                            domain: instrument.series,
                            range: instrument.series.map(color)
                        )
                        .chartLegend(.hidden)
                        .frame(height: 82)
                        .chartXScale(range: .plotDimension(startPadding: 5, endPadding: 18))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(IOSTheme.cyan.opacity(0.16))
                                AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(IOSTheme.cyan.opacity(0.12))
                                AxisValueLabel().font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 10) {
                            ForEach(instrument.series.filter { series in values.contains { $0.series == series } }, id: \.self) { series in
                                HStack(spacing: 3) { Rectangle().fill(color(series)).frame(width: 10, height: 2); Text(series) }
                            }
                        }.font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }.padding(7).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
            }
        }
    }
}

private struct IOSSiteOverview: View {
    @EnvironmentObject private var model: DashboardModel
    let query: String
    var body: some View {
        let daylight = model.presentationResources(viewID: "overview", sectionID: "daylight").first
        let air = model.presentationResources(viewID: "overview", sectionID: "air-quality").first
        let infrastructure = model.presentationResources(viewID: "overview", sectionID: "infrastructure")
        VStack(spacing: 10) {
            if let daylight {
                NavigationLink(value: "habitat") { IOSDaylightPanel(resource: daylight, state: model.displayStatesByResource[daylight.id] ?? []) }
                    .buttonStyle(IOSVintagePressStyle())
            }
            if let air {
                NavigationLink(value: "habitat") { IOSAirQualityPanel(resource: air, state: model.displayStatesByResource[air.id] ?? [], history: model.airQualityHistory, summaryOnly: true) }
                    .buttonStyle(IOSVintagePressStyle())
            }
            IOSHomeCard(title: "Solar & Storage", subtitle: "24-hour production and charge", destination: "energy") { IOSPowerInstruments(points: model.energyHistory) }
            IOSHomeCard(title: "Security", subtitle: "alarm summary", destination: "security") {
                IOSHomeMetrics(values: [("Partition", metric("alarm", "partition_mode")), ("Ready", metric("alarm", "ready")), ("LCD", metric("alarm", "lcd_line_1")), ("Trouble", metric("alarm", "trouble"))])
            }
            IOSHomeCard(title: "Infrastructure", subtitle: "network • storage • protected power", destination: "network") { IOSOverviewStrip(resources: infrastructure) }
            IOSRecentActivity(events: model.meaningfulRecentEvents(limit: 8), resources: model.resources)
        }
    }
    private func metric(_ resource: String, _ metric: String) -> String { model.displayStates.first { $0.resource == resource && $0.metric == metric }?.display ?? "—" }
}

private struct IOSRecentActivity: View {
    let events: [SkyStateEvent]
    let resources: [SkyResource]
    @State private var expanded = false
    var body: some View {
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 0) { ForEach(events) { event in
                    HStack(spacing: 6) {
                        Text(Date(timeIntervalSince1970: Double(event.observed_at_ms) / 1000).formatted(date: .omitted, time: .shortened)).frame(width: 54, alignment: .leading)
                        Text(resources.first { $0.id == event.resource }?.pretty_name ?? event.resource).bold().lineLimit(1)
                        Spacer(); Text(event.new_value.description).lineLimit(1)
                    }.font(.system(size: 8, design: .monospaced)).padding(.horizontal, 7).frame(height: 28).background(IOSTheme.inset)
                } }.padding(.top, 7)
            } label: { HStack { Image(systemName: "clock.arrow.circlepath"); Text("Recent Activity").font(.caption.monospaced().bold()); Spacer(); Text("\(events.count)").font(.caption2.monospaced()) }.foregroundStyle(IOSTheme.cyan) }
            .padding(11).iosVintagePanel()
        }
    }
}

private struct IOSOverviewStrip: View {
    @EnvironmentObject private var model: DashboardModel
    let resources: [SkyResource]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(resources) { resource in
                let rows = (model.displayStatesByResource[resource.id] ?? []).filter { $0.metric != "health" && $0.visibility != "internal" }.sorted { ($0.display_priority ?? 50) < ($1.display_priority ?? 50) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle().fill(resource.severity == "critical" ? .red : resource.severity == "warning" ? IOSTheme.amber : resource.availability == "online" ? IOSTheme.phosphor : .gray).frame(width: 7, height: 7)
                        Text(resource.pretty_name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    ForEach(Array(rows.prefix(2))) { row in
                        HStack(spacing: 3) { Text(row.label ?? row.metric).foregroundStyle(.secondary).lineLimit(1); Spacer(); Text(row.display).monospacedDigit().lineLimit(1) }.font(.system(size: 8))
                    }
                    if rows.isEmpty { Text(resource.id).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(8).frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading).iosVintagePanel()
            }
        }
    }
}

private struct IOSFolderTab: View {
    let title: String
    var body: some View {
        HStack(spacing: 0) {
            Text(title).font(.caption.monospaced().bold()).foregroundStyle(IOSTheme.cyan)
                .padding(.horizontal, 12).frame(height: 27).iosVintagePanel(IOSTheme.face)
            Rectangle().fill(IOSTheme.highlight.opacity(0.45)).frame(height: 1)
        }.padding(.top, 5)
    }
}

private func filteredResources(_ all: [SkyResource], section: String, query: String) -> [SkyResource] {
    all.filter { resource in
        resource.lifecycle == "active" && resource.class != "network-port" && resource.class != "storage-disk" && resource.class != "storage-vdev" &&
        (section == "overview" ? resource.pinned || resource.importance == "critical" : resource.presentation_home == section) &&
        (query.isEmpty || ([resource.pretty_name, resource.id, resource.address, resource.room, resource.asset_tag, resource.notes] + resource.groups).joined(separator: " ").localizedCaseInsensitiveContains(query))
    }.sorted {
        if section == "security" && ($0.class == "alarm-panel") != ($1.class == "alarm-panel") {
            return $0.class == "alarm-panel"
        }
        if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
        if section == "lighting" && $0.room != $1.room { return $0.room.localizedStandardCompare($1.room) == .orderedAscending }
        return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
    }
}

private func icon(_ section: String) -> String {
    ["overview":"house", "habitat":"sofa", "security":"lock.shield", "lighting":"lightbulb", "climate":"thermometer", "energy":"bolt", "network":"network", "compute":"server.rack", "storage":"externaldrive", "inventory":"list.bullet.rectangle", "offline":"wifi.slash"][section] ?? "circle"
}

private struct IOSResourceCard: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var editingAsset = false
    private var controlledMetrics: Set<String> {
        if resource.adapter.hasPrefix("shelly.") { return ["power", "brightness"] }
        if resource.class == "thermostat" { return ["heat_setpoint", "cool_setpoint", "mode", "fan_mode", "fan_state"] }
        if resource.adapter == "envisalink.tpi" { return ["keypad_line1", "keypad_line2", "keypad_beep"] }
        return []
    }
    private var facts: [StateRow] {
        if resource.adapter == "meshtastic.tcp" { return [] }
        return Array(state.filter { $0.metric != "health" && $0.visibility != "internal" && !controlledMetrics.contains($0.metric) }
            .sorted { ($0.display_priority ?? 50) < ($1.display_priority ?? 50) }.prefix(5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
                Text(resource.pretty_name).font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Text(model.isControlPending(resource.id) ? "Pending" : resource.availability.capitalized)
                    .font(.caption.monospaced()).foregroundStyle(model.isControlPending(resource.id) ? IOSTheme.cyan : resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber)
                Button { editingAsset = true } label: {
                    Image(systemName: "ellipsis").font(.caption.bold()).frame(width: 28, height: 24).iosVintagePanel(IOSTheme.face)
                }.buttonStyle(IOSVintagePressStyle())
            }
            Text(resource.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
            if resource.photo_available { IOSAssetPhotoThumbnail(resource: resource) }
            if !resource.asset_tag.isEmpty { Text("Asset \(resource.asset_tag)").font(.caption2.monospaced()).foregroundStyle(.secondary) }
            if !resource.address.isEmpty { Text(resource.address).font(.caption.monospaced()).foregroundStyle(.secondary) }
            if !resource.room.isEmpty { Text(resource.room).font(.caption).foregroundStyle(.secondary) }
            ForEach(facts) { row in
                HStack { Text(row.label ?? row.metric.replacingOccurrences(of: "_", with: " ")); Spacer(); Text(row.display).monospacedDigit().foregroundStyle(.white) }
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if resource.adapter.hasPrefix("shelly.") {
                IOSLightControls(resource: resource, state: state)
            }
            if resource.class == "thermostat" { IOSThermostatControls(resource: resource, state: state) }
            if resource.adapter == "dyson.mqtt" { IOSDysonControls(resource: resource, state: state) }
            if resource.adapter == "meshtastic.tcp" { IOSMeshRadioPanel(resource: resource) }
            if resource.class == "network-switch" || resource.class == "router" || resource.class == "access-point" {
                IOSNetworkChildren(parent: resource)
            }
            if resource.class == "network-station" { IOSNetworkChildren(parent: resource) }
            if resource.adapter == "tapo.rtsp" { IOSCameraControl(resource: resource) }
            if resource.adapter == "envisalink.tpi" { IOSAlarmControls(resource: resource, state: state) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).iosVintagePanel()
        .overlay(alignment: .leading) { Rectangle().fill(resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 3) }
        .sheet(isPresented: $editingAsset) { IOSAssetEditor(resource: resource).environmentObject(model) }
    }
}

private struct IOSMeshRadioPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    private var radio: MeshRadioProjection { model.meshRadioProjection(for: resource) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                counter("Role", radio.role.display); counter("Known", radio.knownNodes.display)
                counter("24 h", radio.recentNodes.display); counter("Direct", radio.directNodes.display)
            }
            utilization("Channel", radio.channelUtilization)
            utilization("Transmit", radio.airUtilization)
            detail("Radio", radio.localName.display, "Node", radio.localID.display)
            detail("Hardware", radio.hardware.display, "Firmware", radio.firmware.display)
            detail("Uptime", radio.uptime.display, "Activity", radio.latestActivity.display)
        }.padding(9).background(IOSTheme.inset.opacity(0.72)).iosVintagePanel(IOSTheme.inset)
    }
    private func counter(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced().bold()).lineLimit(1).minimumScaleFactor(0.65)
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).iosVintagePanel(IOSTheme.face)
    }
    private func utilization(_ label: String, _ metric: ProjectedMetric) -> some View {
        let value = min(100, max(0, metric.number ?? 0))
        return HStack(spacing: 7) {
            Text(label).font(.system(size: 8, design: .monospaced)).frame(width: 48, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(IOSTheme.background)
                    Rectangle().fill(IOSTheme.cyan).frame(width: proxy.size.width * value / 100)
                }
            }.frame(height: 9).iosVintagePanel(IOSTheme.inset)
            Text(metric.display).font(.caption2.monospacedDigit()).frame(width: 42, alignment: .trailing)
        }
    }
    private func detail(_ left: String, _ leftValue: String, _ right: String, _ rightValue: String) -> some View {
        HStack(spacing: 5) {
            Text(left).foregroundStyle(.secondary); Text(leftValue).monospaced().lineLimit(1)
            Spacer(minLength: 5)
            Text(right).foregroundStyle(.secondary); Text(rightValue).monospaced().lineLimit(1)
        }.font(.caption2)
    }
}

private struct IOSAssetPhotoThumbnail: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    var body: some View {
        Group {
            if let data = model.assetPhotos[resource.id], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Color.clear }
        }.frame(maxWidth: .infinity).frame(height: 150).clipped().background(IOSTheme.inset)
            .task { _ = await model.loadAssetPhoto(resource) }
    }
}

private struct IOSAssetEditor: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    let resource: SkyResource
    @State private var name: String
    @State private var assetTag: String
    @State private var room: String
    @State private var groups: String
    @State private var comment: String
    @State private var notes: String
    @State private var selection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoChanged = false
    @State private var removingPhoto = false
    @State private var saving = false
    @State private var saveError = ""

    init(resource: SkyResource) {
        self.resource = resource
        _name = State(initialValue: resource.pretty_name); _assetTag = State(initialValue: resource.asset_tag)
        _room = State(initialValue: resource.room); _groups = State(initialValue: resource.groups.joined(separator: ", "))
        _comment = State(initialValue: resource.comment); _notes = State(initialValue: resource.notes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                IOSGrid()
                ScrollView {
                    VStack(spacing: 10) {
                        assetField("Pretty name", text: $name)
                        assetField("Asset tag", text: $assetTag)
                        assetField("Room", text: $room)
                        assetField("Groups, comma-separated", text: $groups)
                        assetField("Comment", text: $comment, axis: .vertical)
                        assetField("Notes", text: $notes, axis: .vertical)
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Photo").font(.caption.monospaced()).foregroundStyle(IOSTheme.cyan)
                            Group {
                                if let photoData, let image = UIImage(data: photoData) { Image(uiImage: image).resizable().scaledToFill() }
                                else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity).frame(height: 180).clipped().background(IOSTheme.inset)
                            HStack {
                                PhotosPicker("Choose Photo…", selection: $selection, matching: .images)
                                Spacer()
                                if photoData != nil || resource.photo_available {
                                    Button("Remove", role: .destructive) { photoData = nil; photoChanged = true; removingPhoto = true }
                                }
                            }.buttonStyle(IOSVintagePressStyle())
                        }.padding(11).iosVintagePanel()
                        if !saveError.isEmpty { Text(saveError).font(.caption).foregroundStyle(IOSTheme.amber) }
                    }.padding(12)
                }
            }
            .navigationTitle("Object / Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
        .preferredColorScheme(.dark)
        .task { if resource.photo_available { photoData = await model.loadAssetPhoto(resource) } }
        .onChange(of: selection) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data),
                      let encoded = compressedAssetPhoto(image) else { saveError = "The selected image could not be prepared."; return }
                photoData = encoded; photoChanged = true; removingPhoto = false
            }
        }
    }

    private func assetField(_ label: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.monospaced()).foregroundStyle(IOSTheme.cyan)
            TextField(label, text: text, axis: axis).lineLimit(axis == .vertical ? 3...7 : 1...1)
                .padding(9).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.25)))
        }.padding(10).iosVintagePanel()
    }

    private func save() async {
        saving = true; saveError = ""
        let photo: AssetPhotoUpdate = photoChanged ? (removingPhoto ? .delete : photoData.map { .set($0, mime: "image/jpeg") } ?? .delete) : .unchanged
        let saved = await model.edit(resource, name: name, room: room,
                                     groups: groups.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                     comment: comment, assetTag: assetTag, notes: notes, photo: photo)
        saving = false
        if saved { dismiss() } else { saveError = model.error.isEmpty ? "Asset was not saved." : model.error }
    }
}

private struct IOSAssetEditButton: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    @State private var editing = false
    var body: some View {
        Button { editing = true } label: {
            Image(systemName: "ellipsis").font(.caption.bold()).frame(width: 28, height: 24).iosVintagePanel(IOSTheme.face)
        }.buttonStyle(IOSVintagePressStyle())
            .sheet(isPresented: $editing) { IOSAssetEditor(resource: resource).environmentObject(model) }
    }
}

private func compressedAssetPhoto(_ image: UIImage) -> Data? {
    let scale = min(1, 640 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    for quality in [0.78, 0.62, 0.46, 0.32] {
        if let data = resized.jpegData(compressionQuality: quality), data.count <= 256 * 1024 { return data }
    }
    return nil
}

private struct IOSDysonControls: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    private func flag(_ metric: String) -> Bool { state.first { $0.metric == metric }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
    private func number(_ metric: String) -> Int { Int(state.first { $0.metric == metric }.flatMap { row -> Double? in if case .number(let value) = row.value { return value }; return nil } ?? 1.0) }
    var body: some View {
        if resource.class == "air-purifier" {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    control("On", "power.on", active: flag("power"))
                    control("Off", "power.off", active: !flag("power"))
                    Text(model.isControlPending(resource.id) ? "Sending…" : "Fan \(number("fan_speed"))")
                        .font(.caption2.monospaced()).foregroundStyle(model.isControlPending(resource.id) ? IOSTheme.cyan : .secondary)
                        .frame(maxWidth: .infinity)
                }
                HStack(spacing: 5) { control("−", "dyson.fan_speed.set", ["speed": "\(max(1, number("fan_speed") - 1))"]); control("+", "dyson.fan_speed.set", ["speed": "\(min(10, number("fan_speed") + 1))"]); toggle("Auto", "auto_mode", "dyson.auto.set"); toggle("Night", "night_mode", "dyson.night.set"); toggle("Osc", "oscillation", "dyson.oscillation.set") }
            }
        } else {
            HStack(spacing: 5) { control("Start", "vacuum.start"); control("Pause", "vacuum.pause"); control("Resume", "vacuum.resume"); control("Dock", "vacuum.return_to_dock") }
        }
    }
    private func toggle(_ label: String, _ metric: String, _ action: String) -> some View { control(label, action, ["enabled": flag(metric) ? "false" : "true"], active: flag(metric)) }
    private func control(_ label: String, _ action: String, _ parameters: [String: String] = [:], active: Bool = false) -> some View {
        Button { Task { await model.invoke(resource, action: action, parameters: parameters) } } label: { Text(label).font(.caption2.monospaced().bold()).foregroundStyle(active ? IOSTheme.phosphor : .secondary).frame(maxWidth: .infinity, minHeight: 27).iosVintagePanel(active ? IOSTheme.face : IOSTheme.panel) }.buttonStyle(IOSVintagePressStyle()).disabled(model.isControlPending(resource.id))
    }
}

private struct IOSPowerInstruments: View {
    let points: [EnergyChartPoint]
    var body: some View {
        ForEach([("Solar Production", "W", IOSTheme.amber), ("Powerwall Charge", "%", IOSTheme.cyan)], id: \.0) { series, unit, color in
            let values = points.filter { $0.series == series }
            VStack(alignment: .leading, spacing: 8) {
                Text(series).font(.headline)
                if values.isEmpty {
                    HStack {
                        Spacer()
                        Text("History unavailable").font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                    }.frame(height: 145).background(IOSTheme.inset)
                } else {
                    Chart(values) { point in
                        AreaMark(x: .value("Time", point.date), y: .value(unit, point.value)).foregroundStyle(color.opacity(0.18))
                        LineMark(x: .value("Time", point.date), y: .value(unit, point.value)).foregroundStyle(color).lineStyle(.init(lineWidth: 2))
                    }
                    .frame(height: 145)
                    .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 24))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(IOSTheme.cyan.opacity(0.18))
                            AxisTick().foregroundStyle(IOSTheme.cyan.opacity(0.45))
                            AxisValueLabel(format: .dateTime.hour().minute())
                                .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(12).iosVintagePanel()
        }
    }
}

private struct IOSPowerFlowPanel: View {
    let projection: EnergyFlowProjection
    private var charge: Double { min(100, max(0, projection.charge.number ?? 0)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "bolt.house.fill").font(.title2).foregroundStyle(IOSTheme.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live Power Flow").font(.headline)
                    Text(projection.battery.pretty_name).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(projection.charge.display).font(.title2.monospacedDigit().bold()).foregroundStyle(charge < 20 ? IOSTheme.amber : IOSTheme.phosphor)
                    Text("Powerwall charge").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            IOSSegmentGauge(value: charge, color: charge < 20 ? IOSTheme.amber : IOSTheme.phosphor)
            IOSPowerFlowSchematic(projection: projection)
            IOSHomeMetrics(values: [
                ("Reserve", projection.reserve.display), ("Stored", projection.remaining.display),
                ("Mode", projection.mode.display), ("Grid", projection.gridConnectionLabel)
            ])
        }.padding(12).iosVintagePanel()
    }
}

private struct IOSPowerFlowSchematic: View {
    let projection: EnergyFlowProjection
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let solar = CGPoint(x: width / 2, y: 29)
            let grid = CGPoint(x: 51, y: 112)
            let home = CGPoint(x: width - 51, y: 112)
            let battery = CGPoint(x: width / 2, y: 195)
            Canvas { context, _ in
                connection(context, from: solar, to: home, color: IOSTheme.amber)
                connection(context,
                           from: projection.gridDirection == "Exporting" ? home : grid,
                           to: projection.gridDirection == "Exporting" ? grid : home,
                           color: projection.gridDirection == "Balanced" ? .gray : IOSTheme.cyan)
                connection(context,
                           from: projection.batteryDirection == "Charging" ? home : battery,
                           to: projection.batteryDirection == "Charging" ? battery : home,
                           color: projection.batteryDirection == "Standby" ? .gray : IOSTheme.phosphor)
            }
            flowNode("Solar", projection.solar.display, "sun.max.fill", IOSTheme.amber).position(solar)
            flowNode("Grid", projection.grid.display, "powerlines", IOSTheme.cyan, detail: projection.gridDirection).position(grid)
            flowNode("House", projection.house.display, "house.fill", IOSTheme.amber).position(home)
            flowNode("Battery", projection.batteryPower.display, "battery.75percent", IOSTheme.phosphor, detail: projection.batteryDirection).position(battery)
        }
        .frame(height: 224).background(IOSTheme.inset)
        .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.2), lineWidth: 1))
    }
    private func connection(_ context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var line = Path(); line.move(to: from); line.addLine(to: to)
        context.stroke(line, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [7, 3]))
        let t = 0.62, x = from.x + (to.x - from.x) * t, y = from.y + (to.y - from.y) * t
        let angle = atan2(to.y - from.y, to.x - from.x)
        let size = 6.0
        var arrow = Path(); arrow.move(to: CGPoint(x: x + cos(angle) * size, y: y + sin(angle) * size))
        arrow.addLine(to: CGPoint(x: x + cos(angle + 2.45) * size, y: y + sin(angle + 2.45) * size))
        arrow.addLine(to: CGPoint(x: x + cos(angle - 2.45) * size, y: y + sin(angle - 2.45) * size)); arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }
    private func flowNode(_ title: String, _ value: String, _ icon: String, _ color: Color, detail: String? = nil) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) { Image(systemName: icon); Text(title) }.font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(value).font(.caption.monospacedDigit().bold()).lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.system(size: 6.5, design: .monospaced)).foregroundStyle(.secondary) }
        }.frame(width: 94, height: 52).iosVintagePanel(IOSTheme.face)
    }
}

private struct IOSUPSPanel: View {
    let projection: UPSProjection
    private var charge: Double { min(100, max(0, projection.charge.number ?? 0)) }
    private var load: Double { min(100, max(0, projection.load.number ?? 0)) }
    private var warning: Bool { projection.onBattery && (projection.runtime.number ?? 999) < 15 }
    private var responding: Bool { projection.resource.availability == "online" }
    private var statusColor: Color { !responding || warning ? IOSTheme.amber : IOSTheme.phosphor }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "powerplug.fill").font(.title2).foregroundStyle(IOSTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(projection.resource.pretty_name).font(.headline)
                    Text(projection.resource.address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(statusColor).frame(width: 9, height: 9)
                Text(responding ? projection.statusLabel : "Unavailable").font(.caption.monospaced().bold()).foregroundStyle(statusColor)
            }
            HStack(spacing: 8) {
                upsGauge("Battery", projection.charge.display, charge, IOSTheme.phosphor)
                upsGauge("Load", projection.load.display, load, load > 85 ? IOSTheme.amber : IOSTheme.cyan)
                VStack(spacing: 3) {
                    Text("Runtime").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    Text(projection.runtime.display).font(.title3.monospacedDigit().bold()).foregroundStyle(warning ? IOSTheme.amber : .white)
                    Text(projection.onBattery ? "remaining" : "estimated").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 74).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
            }
            IOSHomeMetrics(values: [
                ("Real power", projection.realPower.display), ("Apparent", projection.apparentPower.display),
                ("Input", projection.inputVoltage.display), ("Output", projection.outputVoltage.display),
                ("Temperature", projection.temperature.display), ("State", projection.statusLabel)
            ])
        }.padding(12).iosVintagePanel()
    }
    private func upsGauge(_ title: String, _ display: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            IOSVerticalSegmentGauge(value: value, color: color)
            Text(display).font(.caption.monospacedDigit().bold())
        }.frame(maxWidth: .infinity, minHeight: 102).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.18), lineWidth: 1))
    }
}

private struct IOSSegmentGauge: View {
    let value: Double
    let color: Color
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<20, id: \.self) { index in
                Rectangle().fill(Double(index + 1) * 5 <= value ? color : IOSTheme.inset)
                    .frame(height: 8).overlay(Rectangle().stroke(IOSTheme.shadow.opacity(0.7), lineWidth: 0.5))
            }
        }.padding(3).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.2), lineWidth: 1))
    }
}

private struct IOSVerticalSegmentGauge: View {
    let value: Double
    let color: Color
    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<10).reversed(), id: \.self) { index in
                Rectangle().fill(Double(index + 1) * 10 <= value ? color : IOSTheme.panel).frame(width: 32, height: 4)
            }
        }.padding(4).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.shadow, lineWidth: 1))
    }
}

private struct IOSNetworkView: View {
    @EnvironmentObject private var model: DashboardModel
    let query: String
    var body: some View {
        let chassis = model.networkChassisProjections(query: query)
        let routers = chassis.filter { $0.device.class == "router" }
        let switching = chassis.filter { $0.device.class != "router" }
        VStack(spacing: 13) {
            IOSFabricLinkPanel(links: model.liveNetworkLinks(query: query))
            if !routers.isEmpty {
                IOSNetworkSectionLabel(title: "Routers", count: routers.count)
                ForEach(routers) { IOSNetworkChassisPanel(projection: $0) }
            }
            if !switching.isEmpty {
                IOSNetworkSectionLabel(title: "Switching & Access", count: switching.count)
                ForEach(switching) { IOSNetworkChassisPanel(projection: $0) }
            }
            if chassis.isEmpty { Text("No matching network equipment").font(.caption.monospaced()).foregroundStyle(.secondary).padding(24) }
        }
    }
}

private struct IOSFabricLinkPanel: View {
    let links: [LiveNetworkLinkProjection]
    private var upCount: Int { links.filter(\.isUp).count }
    var body: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "cable.connector.horizontal").foregroundStyle(IOSTheme.amber)
                    Text("Live Fabric Links").font(.caption.monospaced().bold())
                    Spacer()
                    Circle().fill(upCount == links.count ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 7, height: 7)
                    Text("\(upCount) / \(links.count) up").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    ForEach(links) { link in
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Circle().fill(link.isUp ? IOSTheme.phosphor : link.status == "Down" ? .red : IOSTheme.amber).frame(width: 7, height: 7)
                                endpoint(link.source, port: link.sourcePort.resource, trailing: false)
                                Spacer(minLength: 4)
                                Text(link.status).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(link.isUp ? IOSTheme.phosphor : IOSTheme.amber)
                                Spacer(minLength: 4)
                                endpoint(link.target, port: link.targetPort.resource, trailing: true)
                            }
                            HStack {
                                Text(link.label).foregroundStyle(IOSTheme.cyan)
                                Spacer()
                                Text("\(link.lineRate)  \(link.traffic)").foregroundStyle(.secondary)
                            }.font(.system(size: 8, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.72)
                        }.padding(7).background(IOSTheme.inset)
                            .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.16), lineWidth: 1))
                    }
                }
            }.padding(11).iosNetworkChassis()
        }
    }
    private func endpoint(_ device: SkyResource, port: SkyResource, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(device.pretty_name).font(.system(size: 9, weight: .bold)).lineLimit(1)
            Text(port.pretty_name).font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct IOSNetworkSectionLabel: View {
    let title: String
    let count: Int
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(IOSTheme.amber).frame(width: 4, height: 17)
            Text(title).font(.caption.monospaced().bold()).foregroundStyle(.white)
            Spacer()
            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).frame(height: 31)
        .background(IOSTheme.face.opacity(0.72))
        .overlay(alignment: .bottom) { Rectangle().fill(IOSTheme.inset).frame(height: 2) }
    }
}

private struct IOSNetworkChassisPanel: View {
    let projection: NetworkChassisProjection
    private var online: Bool { projection.device.availability == "online" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: networkIcon).font(.title2).foregroundStyle(IOSTheme.amber).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(projection.device.pretty_name).font(.headline)
                    HStack(spacing: 7) {
                        Text(projection.device.id)
                        if !projection.device.address.isEmpty { Text(projection.device.address) }
                    }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(online ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
                Text(projection.health.display.capitalized).font(.caption2.monospaced()).foregroundStyle(online ? IOSTheme.phosphor : IOSTheme.amber)
                IOSAssetEditButton(resource: projection.device)
            }
            if !projection.facts.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                    ForEach(projection.facts) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label ?? row.metric).font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            Text(row.display).font(.caption2.monospaced()).lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                            .background(IOSTheme.inset.opacity(0.9))
                    }
                }
            }
            if !projection.ports.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Port Map").font(.caption.monospaced().bold()).foregroundStyle(.white)
                        Spacer()
                        Text("\(projection.ports.filter(\.isUp).count) up  ·  \(projection.ports.count) total")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                        ForEach(projection.ports) { IOSNetworkPort(port: $0) }
                    }
                }
                .padding(8).background(IOSTheme.inset.opacity(0.72))
            }
            if !projection.clients.isEmpty { IOSNetworkClientDrawer(clients: projection.clients) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).iosNetworkChassis()
    }
    private var networkIcon: String {
        switch projection.device.class {
        case "router": "network"
        case "access-point": "antenna.radiowaves.left.and.right"
        case "network-station": "cable.connector.horizontal"
        default: "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct IOSNetworkPort: View {
    let port: NetworkPortProjection
    var body: some View {
        VStack(spacing: 4) {
            Rectangle().fill(port.isUp ? IOSTheme.phosphor : Color.gray.opacity(0.28)).frame(height: 8)
            Text(port.resource.pretty_name)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                .frame(height: 23)
            Text(port.lineRate.display == "—" ? (port.isUp ? "linked" : "—") : port.lineRate.display)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(port.isUp ? IOSTheme.cyan : .secondary).lineLimit(1)
            Text("↓ \(port.receiveRate.display)  ↑ \(port.transmitRate.display)")
                .font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.62)
        }
        .padding(6).frame(maxWidth: .infinity, minHeight: 72)
        .background(port.isUp ? IOSTheme.face.opacity(0.46) : IOSTheme.panel.opacity(0.68))
    }
}

private struct IOSNetworkClientDrawer: View {
    let clients: [NetworkClientProjection]
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 5) {
                ForEach(clients) { client in
                    HStack(spacing: 7) {
                        Image(systemName: client.ssid.row == nil ? "desktopcomputer" : "wifi").foregroundStyle(IOSTheme.cyan).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(client.resource.pretty_name).font(.caption.bold()).lineLimit(1)
                            Text([client.address.display, client.ssid.text, client.band.text].compactMap { $0 }.filter { $0 != "—" }.joined(separator: " · "))
                                .font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(); Text(client.signal.display == "—" ? "" : client.signal.display).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }.padding(6).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.15), lineWidth: 1))
                }
            }.padding(.top, 6)
        } label: {
            HStack { Text("Attached Clients").font(.caption.monospaced().bold()); Spacer(); Text("\(clients.count)").font(.caption2.monospaced()) }.foregroundStyle(IOSTheme.cyan)
        }
    }
}

private struct IOSNetworkChildren: View {
    @EnvironmentObject private var model: DashboardModel
    let parent: SkyResource
    private var ports: [SkyResource] { model.resources.filter { $0.parent == parent.id && $0.class == "network-port" }.sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending } }
    private var clients: [SkyResource] { model.resources.filter { $0.parent == parent.id && $0.class == "network-client" }.sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending } }
    var body: some View {
        if !ports.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ports").font(.caption.monospaced().bold()).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(ports) { port in
                        let rows = model.displayStatesByResource[port.id] ?? []
                        let up = rows.first { $0.metric == "health" }?.value.string == "up" || rows.first { $0.metric == "link" }?.value.description == "on"
                        VStack(spacing: 2) {
                            Text(port.pretty_name).font(.system(size: 7, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
                            Circle().fill(up ? IOSTheme.phosphor : IOSTheme.inset).frame(width: 7, height: 7)
                            Text(rows.first(where: { $0.metric == "line_rate" })?.display ?? (up ? "linked" : "—"))
                                .font(.system(size: 6.5, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity).frame(height: 43).iosVintagePanel(IOSTheme.face)
                    }
                }
            }
        }
        if !clients.isEmpty {
            DisclosureGroup {
                VStack(spacing: 4) {
                    ForEach(clients) { client in
                        let rows = model.displayStatesByResource[client.id] ?? []
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(client.pretty_name).font(.caption.bold()).lineLimit(1)
                                Text(rows.first { $0.metric == "address" }?.display ?? client.address).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text([rows.first { $0.metric == "ssid" }?.display, rows.first { $0.metric == "signal" }?.display].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(6).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.2), lineWidth: 1))
                    }
                }.padding(.top, 5)
            } label: {
                Text("Clients  \(clients.count)").font(.caption.monospaced().bold()).foregroundStyle(IOSTheme.cyan)
            }
        }
    }
}

private struct IOSCameraControl: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    @State private var loading = false
    @State private var session: IOSCameraSession?
    var body: some View {
        Button {
            guard !loading else { return }
            loading = true
            Task { await acquireStream() }
        } label: {
            Label(loading ? "Acquiring Video" : "View Live Video", systemImage: "play.rectangle.fill")
                .font(.caption.monospaced().bold()).frame(maxWidth: .infinity, minHeight: 30).iosVintagePanel(IOSTheme.face)
        }.buttonStyle(IOSVintagePressStyle()).disabled(loading)
        .sheet(item: $session) { session in
            IOSCameraWindow(resource: resource, stream: session.stream, sessionID: session.id)
        }
    }
    private func acquireStream() async {
        defer { loading = false }
        do {
            let stream = try await model.cameraStream(resource)
            session = IOSCameraSession(stream: stream)
        } catch { model.error = String(describing: error) }
    }
}

private struct IOSCameraSession: Identifiable {
    let id = UUID()
    let stream: String
}

private struct IOSCameraWindow: View {
    @Environment(\.dismiss) private var dismiss
    let resource: SkyResource
    let stream: String
    let sessionID: UUID
    var body: some View {
        ZStack {
            IOSGrid()
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) { Text(resource.pretty_name).font(.headline); Text("Live  \(resource.address)").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Close") { dismiss() }.font(.caption.monospaced().bold()).buttonStyle(.plain).padding(7).iosVintagePanel(IOSTheme.face)
                }.padding(10).iosVintagePanel(IOSTheme.face)
                IOSEmbeddedCameraPlayer(stream: stream)
                    .id(sessionID)
                    .aspectRatio(16 / 9, contentMode: .fit).background(.black)
                    .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.4), lineWidth: 2))
                Spacer()
            }.padding(12)
        }.preferredColorScheme(.dark)
    }
}

private struct IOSAlarmControls: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var pendingAction: String?
    private func text(_ metric: String) -> String {
        state.first { $0.metric == metric }?.value.string ?? ""
    }
    private func flag(_ metric: String) -> Bool {
        guard let row = state.first(where: { $0.metric == metric }) else { return false }
        if case .boolean(let value) = row.value { return value }
        return false
    }
    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(text("keypad_line1").padding(toLength: 16, withPad: " ", startingAt: 0))
                Text(text("keypad_line2").padding(toLength: 16, withPad: " ", startingAt: 0))
            }
            .font(.system(size: 17, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.08))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.62, green: 0.74, blue: 0.38))
            .overlay(Rectangle().stroke(IOSTheme.shadow, lineWidth: 2))
            HStack(spacing: 4) {
                lamp("Ready", flag("ready"), IOSTheme.phosphor)
                lamp("Armed", flag("armed"), IOSTheme.amber)
                lamp("Fire", flag("fire"), .red)
                lamp("Alarm", flag("alarm"), .red)
                lamp("Trouble", flag("trouble"), IOSTheme.amber)
                lamp("Bypass", flag("bypass"), IOSTheme.amber)
                lamp("AC", flag("ac_power"), IOSTheme.phosphor)
            }
            HStack(spacing: 7) {
                alarmButton("Stay", "alarm.arm_stay")
                alarmButton("Away", "alarm.arm_away")
                alarmButton("Disarm", "alarm.disarm")
            }
        }
        .confirmationDialog("Confirm alarm command", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }), titleVisibility: .visible) {
            if let pendingAction { Button("Send command") { Task { await model.invoke(resource, action: pendingAction); self.pendingAction = nil } } }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        }
    }
    private func alarmButton(_ label: String, _ action: String) -> some View {
        Button { pendingAction = action } label: {
            Text(label).font(.caption.monospaced().bold()).frame(maxWidth: .infinity, minHeight: 29).iosVintagePanel(IOSTheme.face)
        }.buttonStyle(IOSVintagePressStyle())
    }
    private func lamp(_ label: String, _ active: Bool, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Circle().fill(active ? color : IOSTheme.inset).frame(width: 8, height: 8)
                .overlay(Circle().stroke(IOSTheme.highlight, lineWidth: 0.5))
            Text(label).font(.system(size: 6.5, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity).frame(height: 31).iosVintagePanel(IOSTheme.face)
    }
}

private struct IOSAlarmPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    private var partition: String { state.first { $0.metric == "partition_mode" }?.display ?? "Unknown" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill").foregroundStyle(IOSTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(resource.pretty_name).font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(partition).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
                Text(resource.availability.capitalized).font(.caption2.monospaced()).foregroundStyle(.secondary)
                IOSAssetEditButton(resource: resource)
            }
            IOSAlarmControls(resource: resource, state: state)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).iosVintagePanel()
        .overlay(alignment: .leading) { Rectangle().fill(resource.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 3) }
    }
}

private struct IOSStorageView: View {
    @EnvironmentObject private var model: DashboardModel
    let query: String
    private var pools: [SkyResource] {
        model.resources.filter { resource in
            guard resource.class == "storage-pool" else { return false }
            let related = model.resources.filter { $0.id.hasPrefix(resource.id + "/") }
            return query.isEmpty || ([resource.pretty_name, resource.id] + related.flatMap { [$0.pretty_name, $0.id] })
                .joined(separator: " ").localizedCaseInsensitiveContains(query)
        }.sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending }
    }
    private var shares: [SkyResource] {
        model.resources.filter { $0.class == "storage-share" && (query.isEmpty || [$0.pretty_name, $0.id].joined(separator: " ").localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(spacing: 9) {
            ForEach(pools) { pool in IOSPoolPanel(pool: pool) }
            ForEach(shares) { share in IOSStorageSharePanel(share: share) }
            if pools.isEmpty && shares.isEmpty {
                Text("No matching storage").font(.callout.monospaced()).foregroundStyle(.secondary).padding(30)
            }
        }
    }
}

private struct IOSPoolPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let pool: SkyResource
    private var rows: [StateRow] { model.displayStatesByResource[pool.id] ?? [] }
    private var capacity: StorageCapacityProjection { model.storageCapacityProjection(for: pool) }
    private var arrays: [SkyResource] { model.resources.filter { $0.class == "storage-vdev" && $0.parent == pool.id }.sorted { $0.pretty_name < $1.pretty_name } }
    private func metric(_ name: String) -> String { rows.first { $0.metric == name }?.display ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "externaldrive.fill").foregroundStyle(IOSTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pool.pretty_name).font(.headline)
                    Text(pool.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Text(metric("health")).font(.caption.monospaced().bold()).foregroundStyle(metric("health") == "ONLINE" ? IOSTheme.phosphor : IOSTheme.amber)
                IOSAssetEditButton(resource: pool)
            }
            IOSStorageCapacityGauge(projection: capacity)
            HStack { storageFact("Used", metric("allocated")); storageFact("Free", metric("free")); storageFact("Capacity", metric("size")) }
            ForEach(arrays) { array in IOSArrayPanel(pool: pool, array: array) }
        }.padding(12).iosVintagePanel()
    }
    private func storageFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary); Text(value).font(.caption.monospacedDigit().bold()) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSStorageSharePanel: View {
    @EnvironmentObject private var model: DashboardModel
    let share: SkyResource
    private var capacity: StorageCapacityProjection { model.storageCapacityProjection(for: share) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.connected.to.line.below").foregroundStyle(IOSTheme.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(share.pretty_name).font(.headline)
                    Text(share.id).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(share.availability == "online" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 8, height: 8)
                Text(capacity.health.display.capitalized).font(.caption2.monospaced()).foregroundStyle(.secondary)
                IOSAssetEditButton(resource: share)
            }
            IOSStorageCapacityGauge(projection: capacity)
            HStack {
                storageFact("Used", capacity.allocated.display)
                storageFact("Free", capacity.free.display)
                storageFact("Capacity", capacity.size.display)
            }
            if share.roles.contains("file-listing") { IOSBackupFileDisclosure(share: share) }
        }.padding(12).iosVintagePanel()
    }
    private func storageFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IOSBackupFileDisclosure: View {
    @EnvironmentObject private var model: DashboardModel
    let share: SkyResource
    @State private var expanded = false
    private var listing: SkyStorageFileListing? { model.storageFileListings[share.id] }
    private var loading: Bool { model.storageFilesLoading.contains(share.id) }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(listing?.available == true ? "Newest first · \(listing?.files.count ?? 0) shown" : listing?.message ?? "Querying backup storage…")
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await model.loadStorageFiles(share, force: true) } }
                        .font(.caption2.monospaced().bold()).disabled(loading)
                }
                if loading { Text("Reading directory /////").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(IOSTheme.amber) }
                if let listing, listing.available {
                    ForEach(listing.files) { file in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name).font(.caption2.monospaced()).lineLimit(1)
                            HStack { Text(file.display_size ?? "—"); Spacer(); Text(file.modified); Text(file.age) }
                                .font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                        }.padding(7).background(IOSTheme.inset)
                    }
                    if listing.files.isEmpty { Text("No backup files reported").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(7) }
                }
            }.padding(.top, 6)
        } label: {
            HStack { Image(systemName: "clock.arrow.circlepath"); Text("Recent Backup Files").font(.caption.monospaced().bold()) }
        }
        .tint(IOSTheme.cyan)
        .onChange(of: expanded) { _, isExpanded in if isExpanded { Task { await model.loadStorageFiles(share) } } }
    }
}

private struct IOSStorageCapacityGauge: View {
    let projection: StorageCapacityProjection
    private var used: Double { min(100, max(0, projection.utilization.number ?? 0)) }
    private var color: Color {
        switch projection.utilization.row?.severity {
        case "critical": .red
        case "warning": IOSTheme.amber
        default: IOSTheme.cyan
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Capacity").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text(projection.utilization.display).font(.caption.monospacedDigit().bold()).foregroundStyle(color)
            }
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    Rectangle().fill(Double(index + 1) * 5 <= used ? color : IOSTheme.panel)
                        .frame(height: 11)
                }
            }
            .padding(4).background(IOSTheme.inset)
            .overlay(Rectangle().stroke(Color.black.opacity(0.9), lineWidth: 1))
        }
    }
}

private struct IOSArrayPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let pool: SkyResource
    let array: SkyResource
    private var disks: [SkyResource] {
        model.resources.filter { disk in
            disk.class == "storage-disk" && disk.id.hasPrefix(pool.id + "/disk/") &&
            model.states.first { $0.resource == disk.id && $0.metric == "vdev" }?.value.string == array.pretty_name
        }.sorted { $0.pretty_name < $1.pretty_name }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Image(systemName: "square.stack.3d.up.fill"); Text(array.pretty_name).font(.caption.monospaced().bold()); Spacer(); Text(health(array.id)).font(.caption2.monospaced()).foregroundStyle(health(array.id) == "ONLINE" ? IOSTheme.phosphor : IOSTheme.amber) }
            ForEach(disks) { disk in
                HStack(spacing: 6) {
                    Circle().fill(health(disk.id) == "ONLINE" ? IOSTheme.phosphor : IOSTheme.amber).frame(width: 7, height: 7)
                    Text(diskName(disk)).font(.caption2.monospaced()).lineLimit(1).minimumScaleFactor(0.65)
                    Spacer(); Text(health(disk.id)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }.padding(8).background(IOSTheme.inset).overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.22), lineWidth: 1))
    }
    private func health(_ id: String) -> String { model.states.first { $0.resource == id && $0.metric == "health" }?.value.string ?? "unknown" }
    private func diskName(_ disk: SkyResource) -> String {
        let name = model.states.first { $0.resource == disk.id && $0.metric == "name" }?.value.string ?? disk.pretty_name
        return name.split(separator: "/").last.map(String.init) ?? name
    }
}

private struct IOSLightControls: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var pendingBrightness: Double?
    private var isOn: Bool {
        state.first { $0.metric == "power" }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false
    }
    private var brightness: Double {
        state.first { $0.metric == "brightness" }.flatMap { if case .number(let value) = $0.value { value } else { nil } } ?? (isOn ? 100 : 0)
    }
    private var dimmable: Bool { resource.adapter == "shelly.dimmer2" || resource.adapter == "shelly.plus-wd" }
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button {
                    Task { await model.invoke(resource, action: isOn ? "power.off" : "power.on") }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                        Text(isOn ? "On" : "Off")
                    }
                    .font(.caption.monospaced().bold()).foregroundStyle(isOn ? IOSTheme.phosphor : .secondary)
                    .frame(minWidth: 72, minHeight: 29).iosVintagePanel(isOn ? IOSTheme.face : IOSTheme.panel)
                }
                .buttonStyle(IOSVintagePressStyle()).contentShape(Rectangle())
                Spacer()
                Text("\(Int(pendingBrightness ?? brightness))%")
                    .font(.callout.monospacedDigit().bold()).foregroundStyle(isOn ? .white : .secondary)
            }
            if dimmable {
                IOSVintageSlider(value: pendingBrightness ?? brightness) { pendingBrightness = $0 } onCommit: { value in
                    Task {
                        await model.invoke(resource, action: "brightness.set", parameters: ["brightness": String(Int(value))])
                        pendingBrightness = nil
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Rectangle().fill(isOn ? IOSTheme.phosphor : IOSTheme.inset).frame(height: 5)
                        .overlay(Rectangle().stroke(IOSTheme.shadow, lineWidth: 1))
                    Text(isOn ? "fixed output" : "switched output").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IOSVintageSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    var body: some View {
        GeometryReader { proxy in
            let clamped = min(100, max(0, value))
            let travel = max(1, proxy.size.width - 18)
            ZStack(alignment: .leading) {
                Rectangle().fill(IOSTheme.inset).frame(height: 9)
                    .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.35), lineWidth: 1))
                Rectangle().fill(IOSTheme.cyan.opacity(0.7)).frame(width: max(0, travel * clamped / 100), height: 5).padding(.leading, 2)
                Rectangle().fill(IOSTheme.face).frame(width: 18, height: 25)
                    .overlay(Rectangle().stroke(IOSTheme.cyan.opacity(0.9), lineWidth: 1))
                    .shadow(color: IOSTheme.shadow, radius: 0, x: 1, y: 1)
                    .offset(x: travel * clamped / 100)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in onChange(min(100, max(0, gesture.location.x / max(1, proxy.size.width) * 100))) }
                .onEnded { gesture in onCommit(min(100, max(0, gesture.location.x / max(1, proxy.size.width) * 100))) })
        }
        .frame(height: 27)
    }
}

private struct IOSThermostatControls: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var pendingMode: String?
    private func number(_ metric: String) -> Double {
        state.first { $0.metric == metric }.flatMap { if case .number(let value) = $0.value { value } else { nil } } ?? 0
    }
    private var observedMode: String {
        guard let row = state.first(where: { $0.metric == "mode" }) else { return "off" }
        return (row.meaning ?? row.value.string ?? row.display_text ?? "off").lowercased()
    }
    private var mode: String { pendingMode ?? observedMode }
    private var fanMode: String {
        state.first { $0.metric == "fan_mode" }.flatMap { $0.value.string }?.lowercased() ?? "auto"
    }
    var body: some View {
        VStack(spacing: 8) {
            setpointRow("Heat", value: number("heat_setpoint"), key: "heat")
            setpointRow("Cool", value: number("cool_setpoint"), key: "cool")
            HStack(spacing: 5) {
                Text("Mode").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach([("Off", "off"), ("Heat", "heat"), ("Cool", "cool"), ("Auto", "auto")], id: \.1) { label, value in
                    Button {
                        pendingMode = value
                        Task {
                            await model.invoke(resource, action: "thermostat.mode.set", parameters: ["mode": value])
                            pendingMode = nil
                        }
                    } label: {
                        HStack(spacing: 2) {
                            if pendingMode == value { ProgressView().controlSize(.mini).tint(IOSTheme.phosphor) }
                            Text(label)
                        }.font(.caption2.monospaced().bold())
                            .foregroundStyle(mode == value ? IOSTheme.phosphor : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 27).iosVintagePanel(mode == value ? IOSTheme.face : IOSTheme.panel)
                    }.buttonStyle(IOSVintagePressStyle()).contentShape(Rectangle()).disabled(pendingMode != nil)
                }
            }
            HStack(spacing: 5) {
                Text("Fan").font(.caption.monospaced()).foregroundStyle(.secondary)
                Text((state.first { $0.metric == "fan_state" }?.value.string ?? "idle").capitalized)
                    .font(.caption2.monospaced()).foregroundStyle((state.first { $0.metric == "fan_state" }?.value.string ?? "") == "running" ? IOSTheme.phosphor : .secondary)
                Spacer(minLength: 4)
                ForEach([("Auto", "auto"), ("On", "on")], id: \.1) { label, value in
                    Button {
                        Task { await model.invoke(resource, action: "thermostat.fan.set", parameters: ["fan": value]) }
                    } label: {
                        Text(label).font(.caption2.monospaced().bold())
                            .foregroundStyle(fanMode == value ? IOSTheme.phosphor : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 27).iosVintagePanel(fanMode == value ? IOSTheme.face : IOSTheme.panel)
                    }.buttonStyle(IOSVintagePressStyle()).contentShape(Rectangle()).disabled(fanMode == value || model.isControlPending(resource.id))
                }
            }
        }
    }
    private func setpointRow(_ label: String, value: Double, key: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            thermostatButton("minus") { set(key, value - 1) }
            Text("\(Int(value))°").font(.title3.monospacedDigit().bold()).frame(width: 48)
            thermostatButton("plus") { set(key, value + 1) }
        }
    }
    private func thermostatButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.caption.bold()).foregroundStyle(IOSTheme.cyan)
                .frame(width: 34, height: 28).iosVintagePanel(IOSTheme.face)
        }.buttonStyle(IOSVintagePressStyle()).contentShape(Rectangle())
    }
    private func set(_ key: String, _ value: Double) {
        Task { await model.invoke(resource, action: "thermostat.setpoints.set", parameters: [key: String(Int(value))]) }
    }
}

private struct IOSSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var host: String
    @Binding var port: Int
    @Binding var clientName: String
    @Binding var token: String
    let reconnect: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("SkyWire") {
                    TextField("Host", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", value: $port, format: .number).keyboardType(.numberPad)
                    TextField("Client identity", text: $clientName).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Text("Tokens are stored in this device's app settings. Use a dedicated, least-privilege credential and never include production tokens in a shared build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(IOSTheme.background)
            .navigationTitle("Settings")
            .toolbar { Button("Done") { reconnect(); dismiss() } }
        }
        .tint(IOSTheme.cyan)
    }
}
