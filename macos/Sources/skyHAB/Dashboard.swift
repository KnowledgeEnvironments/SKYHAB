// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

private struct DetailScrollMetrics: Equatable {
    var progress: CGFloat = 0
    var visibleFraction: CGFloat = 1
    var scrollRange: CGFloat = 0
}

private struct NativeScrollIndicatorSuppressor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            var ancestor: NSView? = view
            while let candidate = ancestor {
                if let scrollView = candidate as? NSScrollView {
                    context.coordinator.attach(to: scrollView)
                    return
                }
                ancestor = candidate.superview
            }
        }
    }
    @MainActor final class Coordinator: NSObject {
        private weak var scrollView: NSScrollView?
        func attach(to scrollView: NSScrollView) {
            guard self.scrollView !== scrollView else { hideNativeIndicator(); return }
            NotificationCenter.default.removeObserver(self)
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
            hideNativeIndicator()
            DispatchQueue.main.async { [weak self] in self?.hideNativeIndicator() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.hideNativeIndicator() }
        }
        @objc private func changed() { hideNativeIndicator() }
        private func hideNativeIndicator() {
            guard let scrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.verticalScroller?.isHidden = true
            scrollView.verticalScroller?.alphaValue = 0
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}

private struct InstrumentedScroll<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @ViewBuilder var body: some View {
        if #available(macOS 15.0, *) {
            ModernInstrumentedScroll { content }
        } else {
            ScrollView { content }
        }
    }
}

@available(macOS 15.0, *)
private struct ModernInstrumentedScroll<Content: View>: View {
    @State private var metrics = DetailScrollMetrics()
    @State private var position = ScrollPosition()
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            content.padding(.trailing, 34)
                .background(NativeScrollIndicatorSuppressor())
        }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: DetailScrollMetrics.self) { geometry in
                let range = max(0, geometry.contentSize.height - geometry.containerSize.height)
                return DetailScrollMetrics(
                    progress: range > 0 ? min(1, max(0, geometry.contentOffset.y / range)) : 0,
                    visibleFraction: min(1, geometry.containerSize.height / max(1, geometry.contentSize.height)),
                    scrollRange: range
                )
            } action: { _, newValue in
                metrics = newValue
            }
            .overlay(alignment: .trailing) {
                if metrics.visibleFraction < 0.999 {
                    VintageScrollControl(metrics: metrics) { progress in
                        position.scrollTo(y: progress * metrics.scrollRange)
                    }
                    .padding(.vertical, 4)
                    .padding(.trailing, 5)
                }
            }
    }
}

private struct VintageScrollControl: View {
    let metrics: DetailScrollMetrics
    let onScroll: (CGFloat) -> Void
    var body: some View {
        VStack(spacing: 2) {
            scrollButton("chevron.up.2", help: "Scroll to top") { onScroll(0) }
            scrollButton("chevron.up", help: "Scroll up") { onScroll(max(0, metrics.progress - 36 / max(1, metrics.scrollRange))) }
            GeometryReader { proxy in
                let thumbHeight = max(38, proxy.size.height * metrics.visibleFraction)
                let travel = max(1, proxy.size.height - thumbHeight)
                ZStack(alignment: .top) {
                    Rectangle().fill(SkyTheme.inset)
                        .overlay(Rectangle().stroke(SkyTheme.cyan.opacity(0.45), lineWidth: 1))
                        .shadow(color: .black.opacity(0.9), radius: 0, x: 1, y: 1)
                    ZStack {
                        Rectangle().fill(SkyTheme.face)
                        VStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle().fill(SkyTheme.cyan.opacity(0.8)).frame(width: 9, height: 1)
                            }
                        }
                    }
                    .frame(width: 16, height: thumbHeight)
                    .overlay(Rectangle().stroke(SkyTheme.cyan.opacity(0.8), lineWidth: 1))
                    .shadow(color: SkyTheme.highlight, radius: 0, x: -1, y: -1)
                    .shadow(color: SkyTheme.shadow, radius: 0, x: 1, y: 1)
                    .offset(y: travel * metrics.progress)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    onScroll(min(1, max(0, (value.location.y - thumbHeight / 2) / travel)))
                })
            }
            scrollButton("chevron.down", help: "Scroll down") { onScroll(min(1, metrics.progress + 36 / max(1, metrics.scrollRange))) }
            scrollButton("chevron.down.2", help: "Scroll to bottom") { onScroll(1) }
        }
        .frame(width: 20)
    }
    private func scrollButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                .foregroundStyle(SkyTheme.cyan).frame(width: 20, height: 17)
                .vintagePanel(SkyTheme.face)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

enum SkyPalette: String, CaseIterable, Identifiable {
    case graphite, indigo, gotham, modesto, olive, ultraviolet, cobalt, jade, ember, cyberdeck
    var id: String { rawValue }
    var title: String {
        switch self {
        case .graphite: "Graphite"; case .indigo: "Indigo"; case .gotham: "Gotham"; case .modesto: "Modesto"; case .olive: "4Dwm Olive"
        case .ultraviolet: "Ultraviolet"; case .cobalt: "Cobalt"; case .jade: "Jade Terminal"; case .ember: "Ember"; case .cyberdeck: "Cyberdeck"
        }
    }
}

enum SkyTheme {
    static let preferenceKey = "skyhab.appearance.palette"
    static var selection: SkyPalette { SkyPalette(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .graphite }
    private static var colors: (Color, Color, Color, Color, Color, Color, Color) {
        switch selection {
        case .graphite:
            (Color(red: 0.075, green: 0.078, blue: 0.073), Color(red: 0.17, green: 0.18, blue: 0.17), Color(red: 0.25, green: 0.26, blue: 0.24), Color(red: 0.025, green: 0.032, blue: 0.028), Color(red: 0.34, green: 0.82, blue: 0.77), Color(red: 1.0, green: 0.64, blue: 0.12), Color(red: 0.42, green: 1.0, blue: 0.48))
        case .indigo:
            (Color(red: 0.035, green: 0.045, blue: 0.095), Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.20, green: 0.22, blue: 0.38), Color(red: 0.015, green: 0.020, blue: 0.055), Color(red: 0.30, green: 0.88, blue: 0.88), Color(red: 1.0, green: 0.60, blue: 0.16), Color(red: 0.48, green: 1.0, blue: 0.62))
        case .gotham:
            (Color(red: 0.025, green: 0.035, blue: 0.050), Color(red: 0.075, green: 0.095, blue: 0.12), Color(red: 0.14, green: 0.17, blue: 0.20), Color(red: 0.008, green: 0.014, blue: 0.020), Color(red: 0.36, green: 0.72, blue: 0.88), Color(red: 0.94, green: 0.54, blue: 0.12), Color(red: 0.35, green: 0.90, blue: 0.66))
        case .modesto:
            (Color(red: 0.075, green: 0.050, blue: 0.078), Color(red: 0.17, green: 0.11, blue: 0.17), Color(red: 0.29, green: 0.20, blue: 0.28), Color(red: 0.032, green: 0.018, blue: 0.034), Color(red: 0.52, green: 0.82, blue: 0.76), Color(red: 1.0, green: 0.62, blue: 0.20), Color(red: 0.62, green: 0.94, blue: 0.52))
        case .olive:
            (Color(red: 0.055, green: 0.060, blue: 0.040), Color(red: 0.14, green: 0.15, blue: 0.095), Color(red: 0.25, green: 0.26, blue: 0.16), Color(red: 0.022, green: 0.027, blue: 0.015), Color(red: 0.50, green: 0.78, blue: 0.63), Color(red: 0.96, green: 0.62, blue: 0.12), Color(red: 0.62, green: 0.94, blue: 0.38))
        case .ultraviolet:
            (Color(red: 0.045, green: 0.018, blue: 0.070), Color(red: 0.13, green: 0.055, blue: 0.20), Color(red: 0.27, green: 0.12, blue: 0.38), Color(red: 0.018, green: 0.006, blue: 0.030), Color(red: 0.82, green: 0.42, blue: 1.0), Color(red: 1.0, green: 0.48, blue: 0.18), Color(red: 0.44, green: 1.0, blue: 0.70))
        case .cobalt:
            (Color(red: 0.018, green: 0.035, blue: 0.090), Color(red: 0.035, green: 0.10, blue: 0.24), Color(red: 0.075, green: 0.20, blue: 0.42), Color(red: 0.006, green: 0.016, blue: 0.045), Color(red: 0.20, green: 0.76, blue: 1.0), Color(red: 1.0, green: 0.58, blue: 0.10), Color(red: 0.34, green: 1.0, blue: 0.58))
        case .jade:
            (Color(red: 0.012, green: 0.052, blue: 0.038), Color(red: 0.025, green: 0.13, blue: 0.085), Color(red: 0.065, green: 0.25, blue: 0.16), Color(red: 0.004, green: 0.025, blue: 0.016), Color(red: 0.22, green: 0.94, blue: 0.68), Color(red: 1.0, green: 0.64, blue: 0.08), Color(red: 0.45, green: 1.0, blue: 0.42))
        case .ember:
            (Color(red: 0.070, green: 0.025, blue: 0.012), Color(red: 0.17, green: 0.060, blue: 0.025), Color(red: 0.31, green: 0.12, blue: 0.045), Color(red: 0.030, green: 0.009, blue: 0.004), Color(red: 1.0, green: 0.46, blue: 0.20), Color(red: 1.0, green: 0.72, blue: 0.10), Color(red: 0.55, green: 1.0, blue: 0.42))
        case .cyberdeck:
            (Color(red: 0.020, green: 0.045, blue: 0.055), Color(red: 0.035, green: 0.12, blue: 0.14), Color(red: 0.075, green: 0.23, blue: 0.25), Color(red: 0.005, green: 0.020, blue: 0.024), Color(red: 0.10, green: 0.96, blue: 0.94), Color(red: 1.0, green: 0.36, blue: 0.50), Color(red: 0.54, green: 1.0, blue: 0.34))
        }
    }
    // A workstation/instrument palette: restrained chassis colors leave the
    // saturated phosphors available for information and alarms.
    static var background: Color { colors.0 }
    static var panel: Color { colors.1 }
    static var face: Color { colors.2 }
    static var inset: Color { colors.3 }
    static let highlight = Color.white.opacity(0.30)
    static let shadow = Color.black.opacity(0.72)
    static var cyan: Color { colors.4 }
    static var amber: Color { colors.5 }
    static var phosphor: Color { colors.6 }
}

private struct VintageSurface: ViewModifier {
    let recessed: Bool
    let tone: Color
    func body(content: Content) -> some View {
        content
            .background { Rectangle().fill(tone) }
            .overlay(alignment: .top) { Rectangle().fill(recessed ? SkyTheme.shadow : SkyTheme.highlight).frame(height: 2) }
            .overlay(alignment: .leading) { Rectangle().fill(recessed ? SkyTheme.shadow : SkyTheme.highlight).frame(width: 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(recessed ? SkyTheme.highlight : SkyTheme.shadow).frame(height: 2) }
            .overlay(alignment: .trailing) { Rectangle().fill(recessed ? SkyTheme.highlight : SkyTheme.shadow).frame(width: 2) }
    }
}

extension View {
    func vintagePanel(_ tone: Color = SkyTheme.panel) -> some View { modifier(VintageSurface(recessed: false, tone: tone)) }
    func vintageInset(_ tone: Color = SkyTheme.inset) -> some View { modifier(VintageSurface(recessed: true, tone: tone)) }
}

struct VintageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(.primary)
            .modifier(VintageSurface(recessed: configuration.isPressed, tone: configuration.isPressed ? SkyTheme.panel : SkyTheme.face))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct VintageIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(VintageSurface(recessed: configuration.isPressed, tone: configuration.isPressed ? SkyTheme.panel : SkyTheme.face))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

struct InstrumentIcon: View {
    let systemName: String
    var active = false
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(active ? SkyTheme.amber : Color.primary)
            .frame(width: 26, height: 24)
            .vintagePanel(SkyTheme.face)
    }
}

struct VintageSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100
    let onCommit: (Double) -> Void
    var body: some View {
        GeometryReader { geometry in
            let span = max(0.001, range.upperBound - range.lowerBound)
            let fraction = min(1, max(0, (value - range.lowerBound) / span))
            let thumbWidth: CGFloat = 11
            ZStack(alignment: .leading) {
                Rectangle().fill(SkyTheme.inset).frame(height: 12).vintageInset()
                Rectangle().fill(SkyTheme.amber.opacity(0.82))
                    .frame(width: max(2, fraction * max(0, geometry.size.width - thumbWidth)), height: 6)
                    .padding(.leading, 3)
                Rectangle().fill(SkyTheme.face).frame(width: thumbWidth, height: 20).vintagePanel(SkyTheme.face)
                    .offset(x: fraction * max(0, geometry.size.width - thumbWidth))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let next = min(1, max(0, gesture.location.x / max(1, geometry.size.width)))
                    value = range.lowerBound + next * span
                }
                .onEnded { _ in onCommit(value) })
        }.frame(height: 20)
    }
}

struct TechnicalGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0.0, through: size.width, by: 32).forEach { x in path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
            stride(from: 0.0, through: size.height, by: 32).forEach { y in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
            context.stroke(path, with: .color(Color.white.opacity(0.025)), lineWidth: 0.5)
        }.background(SkyTheme.background).ignoresSafeArea()
    }
}

struct ResourceGroup: Identifiable {
    let name: String
    let resources: [SkyResource]
    var id: String { name }
}

struct DashboardView: View {
    @EnvironmentObject var model: DashboardModel
    @State private var selection = ProcessInfo.processInfo.environment["SKYHAB_START_SECTION"] ?? "overview"
    @State private var searchText = ""
    @State private var lightingRoom = ""
    @State private var roomSelectorExpanded = false
    @State private var showingPreferences = false
    @AppStorage(SkyTheme.preferenceKey) private var appearancePalette = SkyPalette.graphite.rawValue

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Rectangle().fill(SkyTheme.amber).frame(width: 5, height: 16)
                    Text("skyHAB").font(.custom("Helvetica Neue", size: 15).weight(.bold)).tracking(0.6)
                }.padding(.horizontal, 13).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading).vintagePanel(SkyTheme.face)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.views) { view in
                            Button { selection = view.id } label: {
                                HStack(spacing: 9) {
                                    Rectangle().fill(selection == view.id ? SkyTheme.amber : Color.clear).frame(width: 3, height: 17)
                                    Image(systemName: icon(view.id)).frame(width: 17)
                                    Text(view.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(.custom("Helvetica Neue", size: 11).weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .vintagePanel(selection == view.id ? SkyTheme.face : SkyTheme.panel)
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(6)
                }
                .scrollIndicators(.hidden)
                HStack {
                    Button { showingPreferences = true } label: { InstrumentIcon(systemName: "ellipsis") }
                        .buttonStyle(.plain).help("Preferences")
                    Spacer()
                }.padding(7).vintagePanel(SkyTheme.face)
            }
            .background(SkyTheme.panel)
            .navigationSplitViewColumnWidth(min: 145, ideal: 175, max: 205)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(model.views.first { $0.id == selection }?.title ?? selection.capitalized)
                        .font(.custom("Helvetica Neue", size: 21).weight(.bold)).tracking(0.4)
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass").font(.caption)
                        TextField("Search", text: $searchText).textFieldStyle(.plain).font(.caption.monospaced())
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: { Image(systemName: "xmark").font(.caption2.bold()) }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 9).frame(width: 230, height: 27).vintageInset()
                    Circle().fill(model.connected ? SkyTheme.phosphor : .red).frame(width: 9)
                    Text(model.connected ? "Online" : "Offline").font(.caption.monospaced().bold())
                }
                Rectangle().fill(SkyTheme.highlight).frame(height: 1)
                if selection == "lighting" {
                    HStack(spacing: 9) {
                        Text("Room").font(.caption2.monospaced().bold()).foregroundStyle(.secondary)
                        Button { roomSelectorExpanded.toggle() } label: {
                            HStack(spacing: 8) {
                                Text(lightingRoom.isEmpty ? "All Rooms" : lightingRoom).lineLimit(1)
                                Spacer(minLength: 12); Image(systemName: roomSelectorExpanded ? "chevron.up" : "chevron.down").font(.caption2.bold())
                            }
                            .font(.caption.monospaced().bold()).padding(.horizontal, 10).frame(width: 190, height: 27).vintagePanel(SkyTheme.face)
                        }.buttonStyle(.plain).fixedSize().help("Show lighting in one room")
                        Spacer(minLength: 0)
                    }
                }
                if selection == "lighting" && roomSelectorExpanded {
                    VStack(alignment: .leading, spacing: 3) {
                        Button { lightingRoom = ""; roomSelectorExpanded = false } label: {
                            roomChoiceLabel("All Rooms", selected: lightingRoom.isEmpty)
                        }.buttonStyle(.plain)
                        ForEach(lightingRooms, id: \.self) { room in
                            Button { lightingRoom = room; roomSelectorExpanded = false } label: {
                                roomChoiceLabel(room, selected: lightingRoom == room)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(6).frame(width: 250, alignment: .leading).vintagePanel(SkyTheme.panel)
                }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
                InstrumentedScroll {
                        VStack(alignment: .leading, spacing: 22) {
                            if !searchText.isEmpty { GlobalSearchResults(query: searchText) }
                            else {
                                if selection == "overview" { SiteOverview(query: "", navigate: { selection = $0 }) }
                                if selection == "habitat" { HabitatDashboard(query: "") }
                                if selection == "security" { SecurityDashboard(query: "") }
                                if selection == "energy" && !model.energyHistory.isEmpty { EnergyTrend(points: model.energyHistory) }
                                if selection == "network" { NetworkTopology(query: "") }
                                if selection == "compute" { ComputeTopology(query: "") }
                                if selection == "storage" { StorageArrays(query: "") }
                                if selection == "inventory" { InventoryMatrix(query: "") }
                                if !["overview", "habitat", "security", "network", "compute", "storage", "inventory"].contains(selection) { ForEach(grouped) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        if !group.name.isEmpty { Text(group.name.uppercased()).font(.custom("Helvetica Neue", size: 11).weight(.bold)).tracking(0.4).foregroundStyle(SkyTheme.cyan) }
                                        if selection == "lighting" {
                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 310), spacing: 9, alignment: .top)], alignment: .leading, spacing: 9) {
                                                ForEach(group.resources) { resource in CompactLightCard(resource: resource, state: state(for: resource.id)) }
                                            }
                                        } else {
                                            LazyVStack(spacing: 10) {
                                                ForEach(group.resources) { resource in ResourceCard(resource: resource, state: state(for: resource.id)) }
                                            }
                                        }
                                    }
                                } }
                            }
                        }
                    }
            }.padding(24)
            .ignoresSafeArea(.container, edges: .top)
            .background { TechnicalGrid() }
            .task { await model.run() }.refreshable { await model.refresh() }
            .sheet(isPresented: $showingPreferences) { AppearancePreferences() }
        }
    }

    private var filtered: [SkyResource] {
        var visible = model.resources.filter { $0.class != "network-port" && $0.class != "storage-disk" && $0.class != "storage-vdev" }
        if selection == "offline" {
            var offline = visible.filter { $0.availability == "offline" && $0.lifecycle == "active" }
            if !searchText.isEmpty { let query = searchText.lowercased(); offline = offline.filter { ([ $0.pretty_name, $0.id, $0.address, $0.room, $0.comment] + $0.groups).joined(separator: " ").lowercased().contains(query) } }
            return offline.sorted { $0.pretty_name < $1.pretty_name }
        }
        visible = visible.filter { $0.lifecycle == "active" && $0.availability != "offline" }
        if selection == "lighting" && !lightingRoom.isEmpty { visible = visible.filter { $0.room == lightingRoom } }
        if selection == "storage" { return [] }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            visible = visible.filter { resource in
                ([resource.pretty_name, resource.id, resource.address, resource.room, resource.comment] + resource.groups + resource.roles).joined(separator: " ").lowercased().contains(query)
            }
        }
        let values: [SkyResource]
        if selection == "overview" { values = visible.filter { $0.pinned || $0.importance == "critical" || $0.severity == "warning" || $0.severity == "critical" } }
        else if selection == "inventory" { values = model.resources.filter { $0.class != "network-port" && $0.class != "storage-disk" && $0.class != "storage-vdev" } }
        else { values = visible.filter { $0.presentation_home == selection } }
        return values.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if ($0.pin_order ?? 9999) != ($1.pin_order ?? 9999) { return ($0.pin_order ?? 9999) < ($1.pin_order ?? 9999) }
            let ag = $0.groups.first ?? $0.parent ?? $0.room
            let bg = $1.groups.first ?? $1.parent ?? $1.room
            if ag != bg { return ag.localizedStandardCompare(bg) == .orderedAscending }
            if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
            return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
        }
    }
    private var grouped: [ResourceGroup] {
        let buckets = Dictionary(grouping: filtered) { resource in
            !resource.room.isEmpty && selection == "lighting" ? resource.room : (resource.groups.first ?? (selection == "overview" ? "Important" : resource.class.replacingOccurrences(of: "-", with: " ").capitalized))
        }
        return buckets.keys.sorted().map { ResourceGroup(name: $0, resources: buckets[$0] ?? []) }
    }
    private var lightingRooms: [String] {
        Array(Set(model.resources.filter { $0.lifecycle == "active" && $0.presentation_home == "lighting" && !$0.room.isEmpty }.map(\.room)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func state(for id: String) -> [StateRow] { model.displayStatesByResource[id] ?? [] }
    private func roomChoiceLabel(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 9) {
            Rectangle().fill(selected ? SkyTheme.amber : Color.clear).frame(width: 3, height: 14)
            Text(title).font(.custom("Helvetica Neue", size: 12).weight(selected ? .bold : .medium))
            Spacer(minLength: 0)
            if selected { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(SkyTheme.amber) }
        }
        .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
        .vintagePanel(selected ? SkyTheme.face : SkyTheme.panel)
    }
    private func icon(_ section: String) -> String { ["overview":"house","habitat":"sofa.fill","security":"lock.shield.fill","lighting":"lightbulb","climate":"thermometer","energy":"bolt","network":"network","compute":"server.rack","storage":"externaldrive.fill","inventory":"list.bullet.rectangle","offline":"wifi.slash"][section] ?? "circle" }
}

struct AppearancePreferences: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SkyTheme.preferenceKey) private var selection = SkyPalette.graphite.rawValue
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Appearance").font(.custom("Helvetica Neue", size: 18).weight(.bold)).tracking(0.4)
                Spacer(); Button("Done") { dismiss() }.buttonStyle(VintageButtonStyle())
            }
            Text("Dark workstation palettes").font(.custom("Helvetica Neue", size: 11).weight(.medium)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(SkyPalette.allCases) { palette in
                    Button { selection = palette.rawValue } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 4) {
                                ForEach(preview(palette).indices, id: \.self) { index in
                                    Rectangle().fill(preview(palette)[index]).frame(height: 18)
                                }
                            }.vintageInset()
                            HStack {
                                Text(palette.title).font(.custom("Helvetica Neue", size: 11).weight(.bold))
                                Spacer(); if selection == palette.rawValue { Circle().fill(SkyTheme.phosphor).frame(width: 7, height: 7) }
                            }
                        }.padding(10).vintagePanel(selection == palette.rawValue ? SkyTheme.face : SkyTheme.panel)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(18).frame(width: 540).background { Rectangle().fill(SkyTheme.background) }
    }
    private func preview(_ palette: SkyPalette) -> [Color] {
        switch palette {
        case .graphite: [.gray.opacity(0.65), Color(red: 0.34, green: 0.82, blue: 0.77), .orange]
        case .indigo: [Color.indigo.opacity(0.75), .cyan.opacity(0.8), .orange]
        case .gotham: [Color(red: 0.10, green: 0.15, blue: 0.20), Color(red: 0.36, green: 0.72, blue: 0.88), .orange]
        case .modesto: [Color(red: 0.30, green: 0.18, blue: 0.30), Color(red: 0.52, green: 0.82, blue: 0.76), .orange]
        case .olive: [Color(red: 0.30, green: 0.32, blue: 0.17), Color(red: 0.50, green: 0.78, blue: 0.63), .orange]
        case .ultraviolet: [Color(red: 0.27, green: 0.12, blue: 0.38), Color(red: 0.82, green: 0.42, blue: 1.0), .orange]
        case .cobalt: [Color(red: 0.075, green: 0.20, blue: 0.42), Color(red: 0.20, green: 0.76, blue: 1.0), .orange]
        case .jade: [Color(red: 0.065, green: 0.25, blue: 0.16), Color(red: 0.22, green: 0.94, blue: 0.68), .orange]
        case .ember: [Color(red: 0.31, green: 0.12, blue: 0.045), Color(red: 1.0, green: 0.46, blue: 0.20), .yellow]
        case .cyberdeck: [Color(red: 0.075, green: 0.23, blue: 0.25), Color(red: 0.10, green: 0.96, blue: 0.94), .pink]
        }
    }
}

struct EnergyTrend: View {
    let points: [EnergyChartPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 24 Hours").font(.headline)
            ForEach(["Solar Production", "Powerwall Charge"], id: \.self) { series in
                let values = points.filter { $0.series == series }
                Text(series + "  [" + (values.first?.unit ?? (series == "Solar Production" ? "W" : "%")) + "]").font(.caption.monospaced().bold()).foregroundStyle(SkyTheme.phosphor)
                if values.isEmpty {
                    HStack {
                        Spacer()
                        Text("History unavailable").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                    }.frame(height: 90).padding(8).vintageInset()
                } else {
                    Chart(values) { point in
                        LineMark(x: .value("Time", point.date), y: .value(point.unit, point.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(series == "Solar Production" ? SkyTheme.amber : SkyTheme.phosphor)
                        PointMark(x: .value("Time", point.date), y: .value(point.unit, point.value)).symbolSize(18)
                            .foregroundStyle(series == "Solar Production" ? SkyTheme.amber : SkyTheme.phosphor)
                    }.frame(height: 90).padding(8).vintageInset()
                }
            }
        }.padding().vintagePanel()
    }
}

struct ResourceCard: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var editing = false
    @State private var cameraSession: CameraPresentation?
    @State private var pendingBrightness: Double?
    var health: String { state.first { $0.metric == "health" }?.value.string ?? "unknown" }
    var shownState: [StateRow] {
        if resource.adapter == "meshtastic.tcp" { return [] }
        return Array(state.filter { $0.visibility != "internal" && $0.metric != "health" }
            .sorted { ($0.display_priority ?? 50, $0.label ?? $0.metric) < ($1.display_priority ?? 50, $1.label ?? $1.metric) }
            .prefix(4))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: classIcon).foregroundStyle(iconColor)
                Text(resource.pretty_name).font(.custom("Helvetica Neue", size: 14).weight(.bold))
                if resource.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).help("Pinned") }
                Spacer(); Text(model.isControlPending(resource.id) ? "Pending" : health.lowercased().capitalized).font(.caption).foregroundStyle(model.isControlPending(resource.id) ? SkyTheme.cyan : health == "responding" || health == "ONLINE" ? .green : .orange)
                Button { editing = true } label: { InstrumentIcon(systemName: "pencil") }
                    .buttonStyle(.plain).help("Edit object and asset")
                Menu {
                    Button(resource.pinned ? "Unpin" : "Pin") { Task { await model.setPinned(resource, !resource.pinned) } }
                } label: { InstrumentIcon(systemName: "ellipsis") }.menuStyle(.borderlessButton)
            }
            Text(resource.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            if resource.photo_available { AssetPhotoThumbnail(resource: resource) }
            if !resource.asset_tag.isEmpty { Text("Asset \(resource.asset_tag)").font(.caption2.monospaced()).foregroundStyle(.secondary) }
            if !resource.room.isEmpty || !resource.groups.isEmpty { Text(([resource.room] + resource.groups).filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
            if !resource.address.isEmpty { Text(resource.address).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
            if !resource.comment.isEmpty { Text(resource.comment).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            ForEach(shownState) { row in
                HStack {
                    Text(row.label ?? row.metric.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    if let meaning = row.meaning { Text(meaning).font(.caption).foregroundStyle(.secondary) }
                    Text(row.display).monospacedDigit()
                }
            }
            if resource.adapter.hasPrefix("shelly.") {
                if resource.adapter == "shelly.dimmer2" || resource.adapter == "shelly.plus-wd" {
                    let reported = state.first { $0.metric == "brightness" }.flatMap { row -> Double? in
                        if case .number(let value) = row.value { return value }; return nil
                    } ?? 0
                    HStack {
                        Image(systemName: "sun.min")
                        VintageSlider(value: Binding(get: { pendingBrightness ?? reported }, set: { pendingBrightness = $0 })) { value in
                            Task { await model.invoke(resource, action: "brightness.set", parameters: ["brightness": String(Int(value))]); pendingBrightness = nil }
                        }
                        Text("\(Int(pendingBrightness ?? reported))%").monospacedDigit().frame(width: 42, alignment: .trailing)
                    }
                }
                HStack {
                    Button("On") { Task { await model.invoke(resource, action: "power.on") } }
                    Button("Off") { Task { await model.invoke(resource, action: "power.off") } }
                    Spacer()
                }.buttonStyle(VintageButtonStyle())
            }
            if resource.class == "thermostat" { ThermostatControls(resource: resource, state: state) }
            if resource.adapter == "dyson.mqtt" { DysonControls(resource: resource, state: state) }
            if resource.adapter == "meshtastic.tcp" { MeshRadioPanel(resource: resource) }
            if resource.adapter == "tapo.rtsp" {
                Button { cameraSession = CameraPresentation() } label: { Label("View Camera", systemImage: "play.rectangle.fill") }
                    .buttonStyle(VintageButtonStyle())
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).vintagePanel()
        .contextMenu {
            Button(resource.pinned ? "Unpin" : "Pin") { Task { await model.setPinned(resource, !resource.pinned) } }
            if resource.adapter != "discovered" { Button("Edit…") { editing = true } }
        }
        .sheet(isPresented: $editing) { ResourceEditor(resource: resource) }
        .sheet(item: $cameraSession) { _ in CameraViewer(resource: resource) }
    }
    private var classIcon: String {
        ["light":"lightbulb.fill", "controlled-load":"powerplug.fill", "thermostat":"thermometer.medium", "battery-system":"battery.100percent.bolt", "solar-gateway":"sun.max.fill", "ups":"bolt.fill", "router":"network", "network-switch":"point.3.connected.trianglepath.dotted", "network-station":"cable.connector.horizontal", "access-point":"antenna.radiowaves.left.and.right", "radio-gateway":"antenna.radiowaves.left.and.right", "hyperconverged-host":"server.rack", "compute-node":"cpu", "vm-host":"server.rack", "vm":"shippingbox.fill", "virtual-lisp-machine":"memorychip", "physical-computer":"desktopcomputer", "workstation":"macstudio", "storage-pool":"externaldrive.fill", "storage-share":"externaldrive.connected.to.line.below", "camera":"video.fill", "media-player":"appletv.fill", "air-purifier":"air.purifier.fill", "3d-printer":"printer.fill", "printer":"printer.fill", "alarm-panel":"shield.fill", "av-receiver":"hifireceiver", "robot-vacuum":"circle.circle", "pet-appliance":"pawprint.fill"][resource.class] ?? "circle.hexagongrid.fill"
    }
    private var iconColor: Color {
        resource.severity == "critical" ? .red : resource.severity == "warning" ? .orange : .accentColor
    }
}

private struct MeshRadioPanel: View {
    @EnvironmentObject private var model: DashboardModel
    let resource: SkyResource
    private var radio: MeshRadioProjection { model.meshRadioProjection(for: resource) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                counter("Role", radio.role.display)
                counter("Known", radio.knownNodes.display)
                counter("24 h", radio.recentNodes.display)
                counter("Direct", radio.directNodes.display)
            }
            utilization("Channel", radio.channelUtilization)
            utilization("Transmit", radio.airUtilization)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                detail("Radio", radio.localName.display, "Node", radio.localID.display)
                detail("Hardware", radio.hardware.display, "Firmware", radio.firmware.display)
                detail("Uptime", radio.uptime.display, "Activity", radio.latestActivity.display)
            }.font(.caption2)
        }.padding(9).vintageInset()
    }
    private func counter(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced().bold()).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(6).frame(maxWidth: .infinity, alignment: .leading).vintagePanel(SkyTheme.face)
    }
    private func utilization(_ label: String, _ metric: ProjectedMetric) -> some View {
        let value = min(100, max(0, metric.number ?? 0))
        return HStack(spacing: 7) {
            Text(label).font(.system(size: 8, design: .monospaced)).frame(width: 48, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(SkyTheme.inset)
                    Rectangle().fill(SkyTheme.cyan).frame(width: proxy.size.width * value / 100)
                }.vintageInset()
            }.frame(height: 10)
            Text(metric.display).font(.caption2.monospacedDigit()).frame(width: 42, alignment: .trailing)
        }
    }
    private func detail(_ left: String, _ leftValue: String, _ right: String, _ rightValue: String) -> some View {
        GridRow {
            Text(left).foregroundStyle(.secondary); Text(leftValue).monospaced().lineLimit(1)
            Text(right).foregroundStyle(.secondary); Text(rightValue).monospaced().lineLimit(1)
        }
    }
}

private struct AssetPhotoThumbnail: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    var body: some View {
        Group {
            if let data = model.assetPhotos[resource.id], let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else { Color.clear }
        }.frame(maxWidth: .infinity).frame(height: 105).clipped().vintageInset()
            .task { _ = await model.loadAssetPhoto(resource) }
    }
}

private struct CameraPresentation: Identifiable {
    let id = UUID()
}

struct DysonControls: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    private func flag(_ metric: String) -> Bool { state.first { $0.metric == metric }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
    private func number(_ metric: String) -> Int { Int(state.first { $0.metric == metric }.flatMap { row -> Double? in if case .number(let value) = row.value { return value }; return nil } ?? 1.0) }
    var body: some View {
        if resource.class == "air-purifier" {
            VStack(spacing: 7) {
                HStack { Button("On") { invoke("power.on") }; Button("Off") { invoke("power.off") }; Spacer(); Text("Fan \(number("fan_speed"))").font(.caption.monospaced()) }
                HStack { Button("−") { invoke("dyson.fan_speed.set", ["speed": "\(max(1, number("fan_speed") - 1))"]) }; Button("+") { invoke("dyson.fan_speed.set", ["speed": "\(min(10, number("fan_speed") + 1))"]) }; toggle("Auto", "auto_mode", "dyson.auto.set"); toggle("Night", "night_mode", "dyson.night.set"); toggle("Oscillate", "oscillation", "dyson.oscillation.set") }
            }.buttonStyle(VintageButtonStyle())
        } else {
            HStack { Button("Start") { invoke("vacuum.start") }; Button("Pause") { invoke("vacuum.pause") }; Button("Resume") { invoke("vacuum.resume") }; Button("Dock") { invoke("vacuum.return_to_dock") } }.buttonStyle(VintageButtonStyle())
        }
    }
    private func toggle(_ label: String, _ metric: String, _ action: String) -> some View { Button(label) { invoke(action, ["enabled": flag(metric) ? "false" : "true"]) }.foregroundStyle(flag(metric) ? SkyTheme.phosphor : .primary) }
    private func invoke(_ action: String, _ parameters: [String: String] = [:]) { Task { await model.invoke(resource, action: action, parameters: parameters) } }
}

struct CompactLightCard: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    @State private var pendingBrightness: Double?
    private var isOn: Bool {
        state.first { $0.metric == "power" }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false
    }
    private var reportedBrightness: Double {
        state.first { $0.metric == "brightness" }.flatMap { if case .number(let value) = $0.value { value } else { nil } } ?? (isOn ? 100 : 0)
    }
    private var dimmable: Bool { resource.adapter == "shelly.dimmer2" || resource.adapter == "shelly.plus-wd" }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { Task { await model.invoke(resource, action: isOn ? "power.off" : "power.on") } } label: {
                    InstrumentIcon(systemName: isOn ? "lightbulb.fill" : "lightbulb", active: isOn)
                }.buttonStyle(VintageIconPressStyle()).help(isOn ? "Turn off" : "Turn on")
                VStack(alignment: .leading, spacing: 1) {
                    Text(resource.pretty_name).font(.subheadline.bold()).lineLimit(1)
                    Text(resource.room.isEmpty ? resource.id : resource.room).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.isControlPending(resource.id) { Text("Pending").font(.caption2.monospaced()).foregroundStyle(SkyTheme.cyan) }
                MetadataButton(resource: resource)
            }
            if dimmable {
                HStack(spacing: 7) {
                    VintageSlider(value: Binding(get: { pendingBrightness ?? reportedBrightness }, set: { pendingBrightness = $0 })) { value in
                        Task { await model.invoke(resource, action: "brightness.set", parameters: ["brightness": String(Int(value))]); pendingBrightness = nil }
                    }
                    Text("\(Int(pendingBrightness ?? reportedBrightness))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                }
            } else {
                HStack { Text(isOn ? "On" : "Off").font(.caption).foregroundStyle(.secondary); Spacer(); Text(isOn ? "100%" : "0%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .vintagePanel(isOn ? SkyTheme.face : SkyTheme.panel)
    }
}

struct ThermostatControls: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    let state: [StateRow]
    private func number(_ metric: String) -> Double { state.first { $0.metric == metric }.flatMap { if case .number(let v) = $0.value { v } else { nil } } ?? 0 }
    private func text(_ metric: String) -> String { state.first { $0.metric == metric }?.value.string?.lowercased() ?? "" }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Heat"); Spacer()
                Button { set("heat", number("heat_setpoint") - 1) } label: { Image(systemName: "minus") }
                Text("\(Int(number("heat_setpoint")))°").monospacedDigit().frame(width: 38)
                Button { set("heat", number("heat_setpoint") + 1) } label: { Image(systemName: "plus") }
            }
            HStack {
                Text("Cool"); Spacer()
                Button { set("cool", number("cool_setpoint") - 1) } label: { Image(systemName: "minus") }
                Text("\(Int(number("cool_setpoint")))°").monospacedDigit().frame(width: 38)
                Button { set("cool", number("cool_setpoint") + 1) } label: { Image(systemName: "plus") }
            }
            HStack {
                Text("Mode"); Spacer()
                ForEach([("Off", "off"), ("Heat", "heat"), ("Cool", "cool"), ("Auto", "auto")], id: \.1) { label, value in
                    Button(label) { Task { await model.invoke(resource, action: "thermostat.mode.set", parameters: ["mode": value]) } }
                }
            }
            HStack {
                Text("Fan")
                Text(text("fan_state").capitalized).font(.caption.monospaced()).foregroundStyle(text("fan_state") == "running" ? SkyTheme.phosphor : .secondary)
                Spacer()
                ForEach([("Auto", "auto"), ("On", "on")], id: \.1) { label, value in
                    Button { Task { await model.invoke(resource, action: "thermostat.fan.set", parameters: ["fan": value]) } } label: {
                        HStack(spacing: 5) {
                            Circle().fill(text("fan_mode") == value ? SkyTheme.phosphor : Color.secondary.opacity(0.25)).frame(width: 6, height: 6)
                            Text(label)
                        }.font(.caption.monospaced().bold()).padding(.horizontal, 10).padding(.vertical, 6)
                            .vintagePanel(text("fan_mode") == value ? SkyTheme.face : SkyTheme.panel)
                    }.buttonStyle(.plain).disabled(text("fan_mode") == value || model.isControlPending(resource.id))
                }
            }
        }.buttonStyle(VintageButtonStyle())
    }
    private func set(_ key: String, _ value: Double) {
        Task { await model.invoke(resource, action: "thermostat.setpoints.set", parameters: [key: String(Int(value))]) }
    }
}

struct StorageArrays: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    var pools: [SkyResource] { model.resources.filter { pool in
        guard pool.class == "storage-pool" else { return false }
        if query.isEmpty { return true }
        let related = model.resources.filter { $0.id.hasPrefix(pool.id + "/") }
        return ([pool.pretty_name, pool.id] + related.flatMap { [$0.pretty_name, $0.id] }).joined(separator: " ").lowercased().contains(query.lowercased())
    }.sorted {
        if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
        return $0.pretty_name < $1.pretty_name
    } }
    var shares: [SkyResource] { model.resources.filter { $0.class == "storage-share" }.sorted {
        if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
        return $0.pretty_name < $1.pretty_name
    } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(pools) { pool in
                let arrays = model.resources.filter { $0.class == "storage-vdev" && $0.parent == pool.id }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "externaldrive.fill"); Text(pool.pretty_name).font(.title3.bold()); Text(pool.id).font(.caption.monospaced()).foregroundStyle(.tertiary); Spacer(); HealthBadge(state: state(pool.id)); MetadataButton(resource: pool) }
                    StorageCapacityGauge(projection: model.storageCapacityProjection(for: pool))
                    ForEach(arrays.sorted { $0.pretty_name < $1.pretty_name }) { array in
                        ArrayRow(array: array, pool: pool)
                    }
                }.padding().vintagePanel()
            }
            ForEach(shares) { share in
                VStack(alignment: .leading, spacing: 9) { HStack {
                    Image(systemName: "externaldrive.connected.to.line.below")
                    VStack(alignment: .leading) { Text(share.pretty_name).font(.headline); Text(share.id).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                    Spacer(); HealthBadge(state: state(share.id)); MetadataButton(resource: share)
                }
                    StorageCapacityGauge(projection: model.storageCapacityProjection(for: share))
                    let facts = state(share.id).filter { ["latest_file", "latest_modified"].contains($0.metric) }
                    ForEach(facts) { row in HStack { Text(row.label ?? row.metric.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.secondary); Spacer(); Text(row.display).font(.caption.monospaced()).lineLimit(1) }.font(.caption) }
                    if share.roles.contains("file-listing") { BackupFileDisclosure(share: share) }
                }.padding().vintagePanel()
            }
        }
    }
    private func state(_ id: String) -> [StateRow] { model.displayStatesByResource[id] ?? [] }
}

private struct BackupFileDisclosure: View {
    @EnvironmentObject private var model: DashboardModel
    let share: SkyResource
    @State private var expanded = false
    private var listing: SkyStorageFileListing? { model.storageFileListings[share.id] }
    private var loading: Bool { model.storageFilesLoading.contains(share.id) }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(listing?.available == true ? "Newest first · \(listing?.files.count ?? 0) shown" : listing?.message ?? "Querying backup storage…")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await model.loadStorageFiles(share, force: true) } }
                        .buttonStyle(VintageButtonStyle()).disabled(loading)
                }
                if loading { Text("Reading directory /////").font(.caption2.monospaced().bold()).foregroundStyle(SkyTheme.amber) }
                if let listing, listing.available {
                    ForEach(listing.files) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "doc").foregroundStyle(SkyTheme.cyan)
                            Text(file.name).font(.caption.monospaced()).lineLimit(1)
                            Spacer()
                            Text(file.display_size ?? "—").font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                            Text(file.modified).font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 136, alignment: .trailing)
                            Text(file.age).font(.caption2.monospaced()).foregroundStyle(.tertiary).frame(width: 72, alignment: .trailing)
                        }.padding(.horizontal, 7).frame(minHeight: 28).vintageInset(SkyTheme.inset)
                            .help(file.path)
                    }
                    if listing.files.isEmpty { Text("No backup files reported").font(.caption.monospaced()).foregroundStyle(.secondary).padding(8) }
                }
            }.padding(.top, 7)
        } label: {
            HStack { Image(systemName: "clock.arrow.circlepath"); Text("Recent Backup Files").font(.caption.monospaced().bold()) }
        }
        .tint(SkyTheme.cyan)
        .onChange(of: expanded) { _, isExpanded in if isExpanded { Task { await model.loadStorageFiles(share) } } }
    }
}

private struct StorageCapacityGauge: View {
    let projection: StorageCapacityProjection
    private var used: Double { min(100, max(0, projection.utilization.number ?? 0)) }
    private var color: Color { projection.utilization.row?.severity == "critical" ? .red : projection.utilization.row?.severity == "warning" ? SkyTheme.amber : SkyTheme.cyan }
    var body: some View {
        VStack(spacing: 5) {
            HStack { Text("Capacity").font(.caption2.monospaced()).foregroundStyle(.secondary); Spacer(); Text(projection.utilization.display).font(.caption.monospaced().bold()).foregroundStyle(color) }
            HStack(spacing: 2) { ForEach(0..<24, id: \.self) { index in Rectangle().fill(Double(index + 1) * 100 / 24 <= used ? color : SkyTheme.face).frame(height: 12) } }.padding(4).vintageInset()
            HStack { Text("Used \(projection.allocated.display)"); Spacer(); Text("Free \(projection.free.display)"); Spacer(); Text("Total \(projection.size.display)") }.font(.caption2.monospaced()).foregroundStyle(.secondary)
        }
    }
}

struct ArrayRow: View {
    @EnvironmentObject var model: DashboardModel
    let array: SkyResource
    let pool: SkyResource
    var disks: [SkyResource] {
        model.resources.filter { disk in
            guard disk.class == "storage-disk", disk.id.hasPrefix(pool.id + "/disk/") else { return false }
            return model.states.first { $0.resource == disk.id && $0.metric == "vdev" }?.value.string == array.pretty_name
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "square.stack.3d.up.fill"); Text(array.pretty_name).font(.headline); Text(array.id).font(.caption2.monospaced()).foregroundStyle(.tertiary); Spacer(); HealthBadge(state: model.displayStatesByResource[array.id] ?? []); MetadataButton(resource: array) }
            ForEach(disks.sorted { displayName($0) < displayName($1) }) { disk in
                HStack(spacing: 8) {
                    Circle().fill(health(disk) == "ONLINE" ? .green : .red).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName(disk)).font(.caption.monospaced()).lineLimit(1)
                        Text(disk.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer(); Text(health(disk)).font(.caption).foregroundStyle(health(disk) == "ONLINE" ? .green : .red); MetadataButton(resource: disk)
                }
            }
        }.padding(10).vintageInset()
    }
    private func rows(_ disk: SkyResource) -> [StateRow] { model.displayStatesByResource[disk.id] ?? [] }
    private func health(_ disk: SkyResource) -> String { rows(disk).first { $0.metric == "health" }?.value.string ?? "unknown" }
    private func displayName(_ disk: SkyResource) -> String {
        let physical = rows(disk).first { $0.metric == "name" }?.value.string ?? disk.pretty_name
        return physical.split(separator: "/").last.map(String.init) ?? physical
    }
}

struct HealthBadge: View {
    let state: [StateRow]
    var health: String { state.first { $0.metric == "health" }?.value.string ?? "unknown" }
    var body: some View { Text(health.lowercased().capitalized).font(.caption.bold()).foregroundStyle(health == "ONLINE" || health == "responding" ? .green : .red) }
}

struct MetadataButton: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    @State private var editing = false
    @State private var showingDetails = false
    var body: some View {
        Menu {
            Button("Details…", systemImage: "info.circle") { showingDetails = true }
            Button("Edit Object / Asset…", systemImage: "pencil") { editing = true }
            Divider()
            Button(resource.pinned ? "Unpin" : "Pin", systemImage: resource.pinned ? "pin.slash" : "pin") {
                Task { await model.setPinned(resource, !resource.pinned) }
            }
        } label: { InstrumentIcon(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().help("More")
            .sheet(isPresented: $editing) { ResourceEditor(resource: resource) }
            .sheet(isPresented: $showingDetails) { ResourceDetails(resource: resource) }
    }
}

struct ResourceDetails: View {
    @EnvironmentObject var model: DashboardModel
    @Environment(\.dismiss) var dismiss
    let resource: SkyResource
    private var state: [StateRow] { model.displayStatesByResource[resource.id] ?? [] }
    private var health: StateRow? { state.first { $0.metric == "health" } }
    private var latest: StateRow? { state.max { $0.observed_at_ms < $1.observed_at_ms } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.pretty_name).font(.title2.bold())
                    Text(resource.id).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                detailRow("Reachability", health?.display ?? resource.availability.capitalized)
                detailRow("IP address", resource.address.isEmpty ? "—" : resource.address)
                detailRow("Adapter", resource.adapter)
                detailRow("Asset tag", resource.asset_tag.isEmpty ? "—" : resource.asset_tag)
                detailRow("Room", resource.room.isEmpty ? "—" : resource.room)
                detailRow("Last observation", latest.map { Date(timeIntervalSince1970: Double($0.observed_at_ms) / 1000).formatted(date: .abbreviated, time: .standard) } ?? "—")
            }
            if !resource.comment.isEmpty { Divider(); Text(resource.comment).font(.callout).foregroundStyle(.secondary) }
            if !resource.notes.isEmpty { Text(resource.notes).font(.callout).textSelection(.enabled) }
        }.padding(20).frame(minWidth: 390)
    }
    @ViewBuilder private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(value).font(.body.monospaced()).textSelection(.enabled) }
    }
}

struct ResourceEditor: View {
    @EnvironmentObject var model: DashboardModel
    @Environment(\.dismiss) var dismiss
    let resource: SkyResource
    @State private var name: String
    @State private var room: String
    @State private var comment: String
    @State private var assetTag: String
    @State private var notes: String
    @State private var groups: String
    @State private var photoData: Data?
    @State private var photoChanged = false
    @State private var removingPhoto = false
    @State private var saving = false
    @State private var saveError = ""
    init(resource: SkyResource) {
        self.resource = resource; _name = State(initialValue: resource.pretty_name)
        _room = State(initialValue: resource.room); _comment = State(initialValue: resource.comment)
        _assetTag = State(initialValue: resource.asset_tag); _notes = State(initialValue: resource.notes)
        _groups = State(initialValue: resource.groups.joined(separator: ", "))
    }
    var body: some View {
        Form {
            Section("Identity") {
            TextField("Pretty name", text: $name)
            TextField("Asset tag", text: $assetTag)
            TextField("Room", text: $room)
            TextField("Groups (comma-separated)", text: $groups)
            TextField("Comment", text: $comment, axis: .vertical)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
            }
            Section("Photo") {
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if let photoData, let image = NSImage(data: photoData) {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                        }
                    }.frame(width: 112, height: 84).clipped().vintageInset()
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Choose Photo…") { choosePhoto() }
                        if photoData != nil || resource.photo_available {
                            Button("Remove Photo", role: .destructive) { photoData = nil; photoChanged = true; removingPhoto = true }
                        }
                        Text("JPEG or PNG; stored by skyhabd.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !saveError.isEmpty { Text(saveError).foregroundStyle(.red).font(.caption) }
        }
        .padding().frame(width: 500)
        .task { if resource.photo_available { photoData = await model.loadAssetPhoto(resource) } }
        .safeAreaInset(edge: .bottom) { HStack {
            if saving { ProgressView().controlSize(.small) }
            Spacer(); Button("Cancel") { dismiss() }.disabled(saving)
            Button("Save") { Task {
                saving = true; saveError = ""
                let photo: AssetPhotoUpdate = photoChanged ? (removingPhoto ? .delete : photoData.map { .set($0, mime: "image/jpeg") } ?? .delete) : .unchanged
                let saved = await model.edit(resource, name: name, room: room, groups: groups.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, comment: comment, assetTag: assetTag, notes: notes, photo: photo)
                saving = false
                if saved { dismiss() } else { saveError = model.error.isEmpty ? "Metadata was not saved" : model.error }
            } }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
        }.padding() }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.jpeg, .png, .heic]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url), let encoded = compressedAssetPhoto(image) else {
            if panel.url != nil { saveError = "The selected image could not be prepared." }; return
        }
        photoData = encoded; photoChanged = true; removingPhoto = false
    }
}

private func compressedAssetPhoto(_ image: NSImage) -> Data? {
    let source = image.size
    guard source.width > 0, source.height > 0 else { return nil }
    let scale = min(1, 640 / max(source.width, source.height)); let size = NSSize(width: source.width * scale, height: source.height * scale)
    let resized = NSImage(size: size); resized.lockFocus(); image.draw(in: NSRect(origin: .zero, size: size)); resized.unlockFocus()
    guard let tiff = resized.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    for quality in [0.78, 0.62, 0.46, 0.32] {
        if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality]), data.count <= 256 * 1024 { return data }
    }
    return nil
}

struct PortVisualizers: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    var switches: [SkyResource] { model.resources.filter { device in
        guard device.class == "network-switch" || device.class == "network-station" || device.class == "access-point" || device.class == "router" else { return false }
        if query.isEmpty { return true }
        let related = model.resources.filter { $0.parent == device.id }
        return ([device.pretty_name, device.id, device.address] + related.flatMap { [$0.pretty_name, $0.id] }).joined(separator: " ").lowercased().contains(query.lowercased())
    } }
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(switches) { device in
                let ports = model.resources.filter { $0.class == "network-port" && $0.parent == device.id }
                if !ports.isEmpty { SwitchPorts(device: device, ports: ports) }
            }
        }
    }
}

struct SwitchPorts: View {
    @EnvironmentObject var model: DashboardModel
    let device: SkyResource
    let ports: [SkyResource]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(ports.sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending }) { port in
                    let state = model.displayStatesByResource[port.id] ?? []
                    let up = state.first { $0.metric == "link" }.map { if case .boolean(let v) = $0.value { v } else { false } } ?? false
                    let lineRate = state.first { $0.metric == "line_rate" }?.value.string ?? (up ? "linked" : "—")
                    let rx = state.first { $0.metric == "rx_rate" }?.display ?? "—"
                    let tx = state.first { $0.metric == "tx_rate" }?.display ?? "—"
                    VStack(spacing: 3) {
                        Rectangle().fill(up ? SkyTheme.phosphor : .gray.opacity(0.35)).frame(height: 9)
                        Text(port.pretty_name).font(.caption2.bold()).lineLimit(1)
                        Text(lineRate).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        Text("↓ \(rx)  ↑ \(tx)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                    }.padding(5).vintageInset()
                        .help(state.first { $0.metric == "link_downs" }.map { "Link changes: \($0.display)" } ?? "No change count")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
