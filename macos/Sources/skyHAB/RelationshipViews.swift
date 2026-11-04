// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI
import Charts

private struct FolderTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.minX + 7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ConsoleSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 15).weight(.bold)).tracking(1.1)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(FolderTabShape().fill(SkyTheme.face))
                    .overlay(FolderTabShape().stroke(SkyTheme.highlight, lineWidth: 1))
                    .zIndex(1)
                Spacer(minLength: 0)
                Text(subtitle).font(.custom("Helvetica Neue", size: 11).weight(.medium)).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(SkyTheme.highlight).frame(height: 1) }
            content.padding(.top, 10)
        }
    }
}

private struct ResourceGrid: View {
    @EnvironmentObject var model: DashboardModel
    let resources: [SkyResource]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(resources.sorted {
                if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
                return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
            }) { resource in ResourceCard(resource: resource, state: model.displayStatesByResource[resource.id] ?? []) }
        }
    }
}

struct GlobalSearchResults: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    private var results: [SkyResource] {
        model.resources.filter { resource in
            !["network-port", "storage-disk", "storage-vdev"].contains(resource.class) &&
            ([resource.pretty_name, resource.id, resource.class, resource.address, resource.room,
              resource.comment, resource.asset_tag, resource.notes, resource.parent ?? "", resource.lifecycle, resource.presentation_home] + resource.groups + resource.roles)
                .joined(separator: " ").localizedCaseInsensitiveContains(query)
        }.sorted {
            if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
            return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
        }
    }
    var body: some View {
        ConsoleSection(title: "Search", subtitle: "\(results.count) result\(results.count == 1 ? "" : "s") across this site") {
            if results.isEmpty { Text("No matching resources").foregroundStyle(.secondary).padding(.vertical, 18) }
            else { ResourceGrid(resources: results) }
        }
    }
}

struct SiteOverview: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    let navigate: (String) -> Void
    private var active: [SkyResource] { model.resources.filter { $0.lifecycle == "active" && !["network-port","storage-disk","storage-vdev"].contains($0.class) } }
    private func state(_ resource: String, _ metric: String) -> String { model.displayStates.first { $0.resource == resource && $0.metric == metric }?.display ?? "—" }
    var body: some View {
        let daylightSource = model.presentationResources(viewID: "overview", sectionID: "daylight").first?.id ?? ""
        let airSource = model.presentationResources(viewID: "overview", sectionID: "air-quality").first?.id ?? ""
        let powerSources = model.presentationResources(viewID: "overview", sectionID: "power")
        let solarSource = powerSources.first { $0.class == "solar-gateway" }?.id ?? ""
        let batterySource = powerSources.first { $0.class == "battery-system" }?.id ?? ""
        let securitySource = model.presentationResources(viewID: "overview", sectionID: "security").first?.id ?? ""
        let infrastructure = model.presentationResources(viewID: "overview", sectionID: "infrastructure")
        let healthy = infrastructure.filter { $0.availability == "online" && $0.severity != "critical" && $0.severity != "warning" }.count
        VStack(alignment: .leading, spacing: 14) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330, maximum: 560), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            if let sun = model.resources.first(where: { $0.id == daylightSource }) {
                HomeProjection(title: "Daylight", subtitle: "", destination: "habitat", navigate: navigate) {
                    DaylightConsole(resource: sun)
                }
            }
            HomeProjection(title: "Air Quality", subtitle: "site environment", destination: "habitat", navigate: navigate) {
                HomeMetricGrid(values: [("Temperature", state(airSource, "temperature")), ("Humidity", state(airSource, "humidity")), ("PM2.5", state(airSource, "pm2_5")), ("PM10", state(airSource, "pm10")), ("VOC", state(airSource, "voc_index")), ("NO₂", state(airSource, "no2_index"))])
                HomeAirCharts(points: model.airQualityHistory)
            }
            HomeProjection(title: "Solar & Storage", subtitle: "production • load • battery", destination: "energy", navigate: navigate) {
                HomeMetricGrid(values: [("Solar", state(solarSource, "production_power")), ("House", state(batterySource, "load_power")), ("Grid", state(batterySource, "grid_power")), ("Battery", state(batterySource, "state_of_charge"))])
                EnergyTrend(points: model.energyHistory)
            }
            HomeProjection(title: "Security", subtitle: "alarm summary", destination: "security", navigate: navigate) {
                HomeMetricGrid(values: [("Partition", state(securitySource, "partition_mode")), ("Ready", state(securitySource, "ready")), ("Fire", state(securitySource, "fire")), ("Trouble", state(securitySource, "trouble"))])
            }
            HomeProjection(title: "Infrastructure", subtitle: "network • storage • protected power", destination: "network", navigate: navigate) {
                HStack { Text("\(healthy) / \(infrastructure.count)").font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(healthy == infrastructure.count ? SkyTheme.phosphor : SkyTheme.amber); Text("critical systems nominal").font(.caption).foregroundStyle(.secondary); Spacer() }
                OverviewStrip(resources: infrastructure)
            }
        }
        RecentActivity(events: model.meaningfulRecentEvents(), resources: model.resources)
        }
    }
    private func number(_ resource: String, _ metric: String) -> Double { model.displayStates.first { $0.resource == resource && $0.metric == metric }.flatMap { if case .number(let value) = $0.value { value / 100 } else { nil } } ?? 0 }
    private func boolean(_ resource: String, _ metric: String) -> Bool { model.displayStates.first { $0.resource == resource && $0.metric == metric }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
}

private struct RecentActivity: View {
    let events: [SkyStateEvent]
    let resources: [SkyResource]
    @State private var expanded = false
    var body: some View {
        if !events.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 0) { ForEach(events) { event in
                    HStack(spacing: 8) {
                        Text(Date(timeIntervalSince1970: Double(event.observed_at_ms) / 1000).formatted(date: .omitted, time: .shortened)).font(.caption2.monospaced()).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                        Text(resources.first { $0.id == event.resource }?.pretty_name ?? event.resource).font(.caption.bold()).lineLimit(1)
                        Text(event.metric.replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                        Spacer(); Text(event.new_value.description).font(.caption.monospaced()).lineLimit(1)
                    }.padding(.horizontal, 8).frame(height: 28)
                    Divider().overlay(SkyTheme.cyan.opacity(0.08))
                } }.vintageInset().padding(.top, 8)
            } label: { HStack { Image(systemName: "clock.arrow.circlepath").foregroundStyle(SkyTheme.cyan); Text("Recent Activity").font(.caption.monospaced().bold()); Spacer(); Text("\(events.count) changes").font(.caption2.monospaced()).foregroundStyle(.secondary) } }
            .padding(12).vintagePanel()
        }
    }
}

private struct HomeAirCharts: View {
    let points: [EnergyChartPoint]
    private let groups = [("Particles", ["PM2.5", "PM10", "Formaldehyde"]), ("Air Quality Indices", ["VOC", "NO₂"])]
    var body: some View {
        ForEach(groups, id: \.0) { title, series in
            let values = points.filter { series.contains($0.series) }
            if !values.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(title).font(.caption.monospaced().bold()); Spacer(); Text("24 h").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    Chart(values) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Reading", point.value))
                            .foregroundStyle(by: .value("Series", point.series))
                    }.chartLegend(position: .bottom).frame(height: 105)
                }.padding(8).vintageInset()
            }
        }
    }
}

private struct HomeProjection<Content: View>: View {
    let title: String; let subtitle: String; let destination: String; let navigate: (String) -> Void; @ViewBuilder let content: Content
    var body: some View { Button { navigate(destination) } label: { VStack(alignment: .leading, spacing: 9) { HStack { VStack(alignment: .leading, spacing: 1) { Text(title).font(.headline); if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) } }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(SkyTheme.cyan) }; content }.padding(12).frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading).vintagePanel() }.buttonStyle(.plain) }
}

private struct HomeMetricGrid: View {
    let values: [(String, String)]
    var body: some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) { ForEach(values.indices, id: \.self) { index in HStack { Text(values[index].0).foregroundStyle(.secondary); Spacer(); Text(values[index].1).monospacedDigit() }.font(.caption).padding(6).vintageInset() } } }
}

private struct OverviewStrip: View {
    @EnvironmentObject var model: DashboardModel
    let resources: [SkyResource]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 9)], alignment: .leading, spacing: 9) {
            ForEach(resources) { resource in OverviewTile(resource: resource, state: model.displayStatesByResource[resource.id] ?? []) }
        }
    }
}

private struct OverviewTile: View {
    let resource: SkyResource
    let state: [StateRow]
    private var facts: [StateRow] {
        Array(state.filter { $0.metric != "health" && $0.visibility != "internal" }
            .sorted { ($0.display_priority ?? 50) < ($1.display_priority ?? 50) }.prefix(2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(resource.severity == "critical" ? .red : resource.severity == "warning" ? .orange : resource.availability == "online" ? SkyTheme.phosphor : .gray)
                    .frame(width: 7, height: 7)
                Text(resource.pretty_name).font(.subheadline.bold()).lineLimit(1)
                Spacer(); Text(resource.availability).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            ForEach(facts) { row in
                HStack { Text(row.label ?? row.metric.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.secondary); Spacer(); Text(row.display).monospacedDigit() }
                    .font(.caption).lineLimit(1)
            }
            if facts.isEmpty { Text(resource.id).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
        .vintagePanel()
    }
}

struct InventoryMatrix: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    private let widths: [CGFloat] = [190, 185, 135, 125, 125, 185, 150, 115, 105, 105, 90, 36]
    private var resources: [SkyResource] {
        model.resources.filter { resource in
            guard !["network-port", "storage-disk", "storage-vdev"].contains(resource.class) else { return false }
            if query.isEmpty { return true }
            return ([resource.pretty_name, resource.id, resource.class, resource.address, resource.room,
                     resource.parent ?? "", resource.lifecycle, resource.importance, resource.presentation_home] + resource.groups + resource.roles)
                .joined(separator: " ").localizedCaseInsensitiveContains(query)
        }.sorted {
            if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
            return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("\(resources.count) RESOURCES").font(.caption.monospaced().bold()).foregroundStyle(SkyTheme.cyan); Spacer(); Text("Pencil opens the object / asset editor").font(.caption).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                LazyVStack(spacing: 0) {
                    matrixRow(["Pretty name", "Object ID", "Class", "Address", "Room", "Groups", "Parent", "Lifecycle", "Importance", "Home", "State", ""], header: true)
                    ForEach(resources) { resource in
                        HStack(spacing: 0) {
                            cell(resource.pretty_name, 0, leading: true)
                            cell(resource.id, 1, mono: true)
                            cell(resource.class, 2)
                            cell(resource.address, 3, mono: true)
                            cell(resource.room, 4)
                            cell(resource.groups.joined(separator: ", "), 5)
                            cell(resource.parent ?? "", 6, mono: true)
                            cell(resource.lifecycle, 7)
                            cell(resource.importance, 8)
                            cell(resource.presentation_home, 9)
                            cell(resource.availability, 10)
                            MetadataButton(resource: resource).frame(width: widths[11], height: 34)
                        }
                        .background(resource.lifecycle == "active" ? Color.clear : Color.secondary.opacity(0.045))
                        Divider().overlay(SkyTheme.cyan.opacity(0.08))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .vintageInset()
        }
    }
    private func matrixRow(_ values: [String], header: Bool) -> some View {
        HStack(spacing: 0) { ForEach(values.indices, id: \.self) { index in cell(values[index], index, mono: header, leading: header) } }
            .background(header ? SkyTheme.cyan.opacity(0.09) : Color.clear)
    }
    private func cell(_ text: String, _ index: Int, mono: Bool = false, leading: Bool = false) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(mono ? .caption.monospaced() : leading ? .caption.bold() : .caption)
            .foregroundStyle(text.isEmpty ? .tertiary : .primary).lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 7).frame(width: widths[index], height: 34, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(SkyTheme.cyan.opacity(0.07)).frame(width: 1) }
            .help(text)
    }
}

struct HabitatDashboard: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    var body: some View {
        let habitat = model.resources.filter { $0.lifecycle == "active" && $0.presentation_home == "habitat" && (query.isEmpty || ([$0.pretty_name,$0.id,$0.comment] + $0.roles).joined(separator: " ").localizedCaseInsensitiveContains(query)) }
        VStack(alignment: .leading, spacing: 24) {
            if let ephemeris = habitat.first(where: { $0.adapter == "site.ephemeris" }) {
                ConsoleSection(title: "Daylight", subtitle: "sunrise • sunset • solar position") { DaylightConsole(resource: ephemeris) }
            }
            ConsoleSection(title: "Habitat Systems", subtitle: "media • appliances • environmental systems") { ResourceGrid(resources: habitat.filter { $0.adapter != "site.ephemeris" }) }
        }
    }
}

private struct DaylightConsole: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    private var state: [StateRow] { model.displayStatesByResource[resource.id] ?? [] }
    private func text(_ metric: String) -> String { state.first { $0.metric == metric }?.display ?? "—" }
    private func fraction(_ metric: String) -> Double { state.first { $0.metric == metric }.flatMap { if case .number(let value) = $0.value { value / 100 } else { nil } } ?? 0 }
    private var daylight: Bool { state.first { $0.metric == "daylight" }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("site_address")).font(.subheadline.weight(.semibold))
                    Text(text("site_coordinates")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    Text(text("next_transition")).font(.caption.monospaced()).foregroundStyle(daylight ? SkyTheme.amber : SkyTheme.cyan)
                }
                Spacer(); Text(text("solar_phase")).font(.caption.monospaced()).foregroundStyle(daylight ? SkyTheme.amber : SkyTheme.cyan)
            }
            DaylightWave(
                dawn: fraction("sunrise_day_progress"), dusk: fraction("sunset_day_progress"), now: fraction("day_progress"), daylight: daylight,
                morning: [fraction("astronomical_dawn_day_progress"), fraction("nautical_dawn_day_progress"), fraction("civil_dawn_day_progress"), fraction("sunrise_day_progress")],
                evening: [fraction("sunset_day_progress"), fraction("civil_dusk_day_progress"), fraction("nautical_dusk_day_progress"), fraction("astronomical_dusk_day_progress")]
            )
            VStack(spacing: 4) {
                HStack { Text("Threshold"); Spacer(); Text("Dawn").frame(width: 80, alignment: .trailing); Text("Dusk").frame(width: 80, alignment: .trailing) }.foregroundStyle(.secondary)
                ForEach([("Sun", "sunrise", "sunset", SkyTheme.amber), ("Civil · −6°", "civil_dawn", "civil_dusk", SkyTheme.amber.opacity(0.72)), ("Nautical · −12°", "nautical_dawn", "nautical_dusk", SkyTheme.cyan), ("Astronomical · −18°", "astronomical_dawn", "astronomical_dusk", SkyTheme.cyan.opacity(0.55))], id: \.0) { label, dawnMetric, duskMetric, color in
                    HStack(spacing: 6) { Rectangle().fill(color).frame(width: 12, height: 4); Text(label); Spacer(); Text(text(dawnMetric)).frame(width: 80, alignment: .trailing); Text(text(duskMetric)).frame(width: 80, alignment: .trailing) }
                }
            }.font(.caption2.monospaced()).padding(8).vintageInset()
        }.padding(12).vintagePanel()
    }
}

private struct DaylightWave: View {
    let dawn: Double
    let dusk: Double
    let now: Double
    let daylight: Bool
    let morning: [Double]
    let evening: [Double]
    var body: some View {
        Canvas { context, size in
            let left = 14.0, right = size.width - 14, width = right - left
            let horizon = size.height * 0.48, amplitude = size.height * 0.29
            func x(_ fraction: Double) -> Double { left + min(max(fraction, 0), 1) * width }
            func dayY(_ fraction: Double) -> Double { horizon - sin(.pi * (fraction - dawn) / max(0.001, dusk - dawn)) * amplitude }
            let nightLength = max(0.001, 1 - dusk + dawn)
            func nightY(_ fraction: Double) -> Double { let phase = fraction >= dusk ? (fraction - dusk) / nightLength : (1 - dusk + fraction) / nightLength; return horizon + sin(.pi * phase) * amplitude }
            let morningColors = [SkyTheme.cyan.opacity(0.05), SkyTheme.cyan.opacity(0.10), SkyTheme.amber.opacity(0.12)]
            let eveningColors = [SkyTheme.amber.opacity(0.12), SkyTheme.cyan.opacity(0.10), SkyTheme.cyan.opacity(0.05)]
            if morning.count == 4 && evening.count == 4 {
                for index in 0..<3 {
                    var band = Path(); band.addRect(CGRect(x: x(morning[index]), y: 9, width: max(0, x(morning[index + 1]) - x(morning[index])), height: size.height - 32)); context.fill(band, with: .color(morningColors[index]))
                    var eveningBand = Path(); eveningBand.addRect(CGRect(x: x(evening[index]), y: 9, width: max(0, x(evening[index + 1]) - x(evening[index])), height: size.height - 32)); context.fill(eveningBand, with: .color(eveningColors[index]))
                }
            }
            for hour in stride(from: 0, through: 24, by: 3) {
                let position = Double(hour) / 24; var grid = Path(); grid.move(to: CGPoint(x: x(position), y: 9)); grid.addLine(to: CGPoint(x: x(position), y: size.height - 23))
                context.stroke(grid, with: .color(SkyTheme.cyan.opacity(hour % 6 == 0 ? 0.22 : 0.09)), lineWidth: hour % 6 == 0 ? 1 : 0.5)
                if hour % 6 == 0 { context.draw(Text(String(format: "%02d", hour)).font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: x(position), y: size.height - 10)) }
            }
            var dayFill = Path(); dayFill.move(to: CGPoint(x: x(dawn), y: horizon))
            for step in 0...80 { let value = dawn + (dusk - dawn) * Double(step) / 80; dayFill.addLine(to: CGPoint(x: x(value), y: dayY(value))) }
            dayFill.addLine(to: CGPoint(x: x(dusk), y: horizon)); dayFill.closeSubpath(); context.fill(dayFill, with: .color(SkyTheme.amber.opacity(0.22)))
            var dayLine = Path(); for step in 0...80 { let value = dawn + (dusk - dawn) * Double(step) / 80; let point = CGPoint(x: x(value), y: dayY(value)); if step == 0 { dayLine.move(to: point) } else { dayLine.addLine(to: point) } }
            context.stroke(dayLine, with: .color(SkyTheme.amber), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            func drawNight(_ start: Double, _ end: Double) {
                var fill = Path(); fill.move(to: CGPoint(x: x(start), y: horizon))
                for step in 0...40 { let value = start + (end - start) * Double(step) / 40; fill.addLine(to: CGPoint(x: x(value), y: nightY(value))) }
                fill.addLine(to: CGPoint(x: x(end), y: horizon)); fill.closeSubpath(); context.fill(fill, with: .color(SkyTheme.cyan.opacity(0.12)))
                var line = Path(); for step in 0...40 { let value = start + (end - start) * Double(step) / 40; let point = CGPoint(x: x(value), y: nightY(value)); if step == 0 { line.move(to: point) } else { line.addLine(to: point) } }
                context.stroke(line, with: .color(SkyTheme.cyan.opacity(0.72)), lineWidth: 1.5)
            }
            drawNight(0, dawn); drawNight(dusk, 1)
            var horizonLine = Path(); horizonLine.move(to: CGPoint(x: left, y: horizon)); horizonLine.addLine(to: CGPoint(x: right, y: horizon)); context.stroke(horizonLine, with: .color(SkyTheme.highlight.opacity(0.5)), lineWidth: 1)
            for (boundary, label) in [(dawn, "RISE"), (dusk, "SET")] { var marker = Path(); marker.addEllipse(in: CGRect(x: x(boundary) - 4, y: horizon - 4, width: 8, height: 8)); context.fill(marker, with: .color(SkyTheme.amber)); context.draw(Text(label).font(.system(size: 7, weight: .bold, design: .monospaced)).foregroundColor(SkyTheme.amber), at: CGPoint(x: x(boundary), y: horizon - 12)) }
            let currentY = daylight ? dayY(now) : nightY(now); var needle = Path(); needle.move(to: CGPoint(x: x(now), y: 8)); needle.addLine(to: CGPoint(x: x(now), y: size.height - 23)); context.stroke(needle, with: .color(daylight ? SkyTheme.amber : SkyTheme.cyan), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var current = Path(); current.addEllipse(in: CGRect(x: x(now) - 5, y: currentY - 5, width: 10, height: 10)); context.fill(current, with: .color(daylight ? SkyTheme.amber : SkyTheme.cyan))
        }.frame(height: 155).vintageInset()
    }
}

struct SecurityDashboard: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    var body: some View {
        let security = model.resources.filter { $0.lifecycle == "active" && $0.presentation_home == "security" &&
            (query.isEmpty || ([$0.pretty_name,$0.id,$0.comment] + $0.roles).joined(separator: " ").localizedCaseInsensitiveContains(query)) }
        VStack(alignment: .leading, spacing: 18) {
            if let alarm = security.first(where: { $0.class == "alarm-panel" }) {
                ConsoleSection(title: "Alarm", subtitle: "burglar • fire • virtual keypad") { AlarmConsole(resource: alarm) }
            }
            let cameras = security.filter { $0.class == "camera" }
            if !cameras.isEmpty { ConsoleSection(title: "Cameras", subtitle: "live RTSP") { ResourceGrid(resources: cameras) } }
        }
    }
}

private struct AlarmConsole: View {
    @EnvironmentObject var model: DashboardModel
    let resource: SkyResource
    @State private var requestedAction: String?
    private var state: [StateRow] { model.displayStatesByResource[resource.id] ?? [] }
    private func text(_ metric: String) -> String { state.first { $0.metric == metric }?.display.trimmingCharacters(in: .whitespaces) ?? "" }
    private func flag(_ metric: String) -> Bool { state.first { $0.metric == metric }.flatMap { if case .boolean(let value) = $0.value { value } else { nil } } ?? false }
    private var mode: String { text("partition_mode").replacingOccurrences(of: "-", with: " ").capitalized }
    private var confirmationTitle: String {
        switch requestedAction { case "alarm.arm_stay": "Arm Stay?"; case "alarm.arm_away": "Arm Away?"; case "alarm.disarm": "Disarm alarm?"; default: "Confirm alarm action" }
    }
    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: flag("fire") ? "flame.fill" : "shield.lefthalf.filled").font(.title); Text(mode.isEmpty ? "Unknown" : mode).font(.title2.bold()) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 100), spacing: 7, alignment: .leading)], alignment: .leading, spacing: 7) {
                AlarmLamp(label: "Ready", on: flag("ready"), color: SkyTheme.phosphor)
                AlarmLamp(label: "Armed", on: flag("armed"), color: SkyTheme.amber)
                AlarmLamp(label: "Bypass", on: flag("bypass"), color: SkyTheme.amber)
                AlarmLamp(label: "Trouble", on: flag("trouble"), color: .orange)
                AlarmLamp(label: "Fire", on: flag("fire"), color: .red)
                AlarmLamp(label: "Alarm", on: flag("alarm"), color: .red)
            }.frame(maxWidth: 365, alignment: .leading)
        }
    }
    private var keypadDisplay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text("keypad_line1").isEmpty ? "                " : text("keypad_line1"))
            Text(text("keypad_line2").isEmpty ? "                " : text("keypad_line2"))
        }.font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(Color.black.opacity(0.82))
            .padding(.horizontal, 14).padding(.vertical, 9).frame(minWidth: 245, alignment: .leading)
            .vintageInset(Color(red: 0.58, green: 0.76, blue: 0.52))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    statusBlock
                    Spacer(minLength: 8)
                    keypadDisplay
                }
                VStack(alignment: .leading, spacing: 12) {
                    statusBlock.frame(maxWidth: .infinity, alignment: .leading)
                    keypadDisplay
                }
            }
            HStack {
                Button("Arm Stay") { requestedAction = "alarm.arm_stay" }
                Button("Arm Away") { requestedAction = "alarm.arm_away" }
                Button("Disarm", role: .destructive) { requestedAction = "alarm.disarm" }
                Spacer(); Text(resource.address).font(.caption2.monospaced()).foregroundStyle(.tertiary); MetadataButton(resource: resource)
            }.buttonStyle(VintageButtonStyle())
        }.padding(16).vintagePanel(SkyTheme.face)
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { requestedAction != nil }, set: { if !$0 { requestedAction = nil } }), titleVisibility: .visible) {
            if let action = requestedAction {
                Button(action == "alarm.disarm" ? "Disarm" : action == "alarm.arm_stay" ? "Arm Stay" : "Arm Away", role: action == "alarm.disarm" ? .destructive : nil) {
                    requestedAction = nil; Task { await model.invoke(resource, action: action) }
                }
            }
            Button("Cancel", role: .cancel) { requestedAction = nil }
        } message: { Text(requestedAction == "alarm.disarm" ? "This will silence and disarm the panel." : "Any configured bypass policy will be verified before arming.") }
    }
}

private struct AlarmLamp: View {
    let label: String; let on: Bool; let color: Color
    var body: some View { HStack(spacing: 4) { Circle().fill(on ? color : Color.secondary.opacity(0.25)).frame(width: 7, height: 7); Text(label).font(.caption2.monospaced()) }.opacity(on ? 1 : 0.62) }
}

struct NetworkTopology: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FabricLinkPanel(links: model.liveNetworkLinks(query: query))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 390, maximum: 590), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(model.networkChassisProjections(query: query)) { NetworkChassis(projection: $0) }
            }
        }
    }
}

private struct FabricLinkPanel: View {
    let links: [LiveNetworkLinkProjection]
    private var upCount: Int { links.filter(\.isUp).count }
    var body: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "cable.connector.horizontal").foregroundStyle(SkyTheme.amber)
                    Text("Live Fabric Links").font(.caption.monospaced().bold())
                    Spacer()
                    Circle().fill(upCount == links.count ? SkyTheme.phosphor : SkyTheme.amber).frame(width: 7, height: 7)
                    Text("\(upCount) / \(links.count) up").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                VStack(spacing: 3) {
                    ForEach(links) { link in
                        HStack(spacing: 8) {
                            Circle().fill(link.isUp ? SkyTheme.phosphor : link.status == "Down" ? .red : SkyTheme.amber).frame(width: 7, height: 7)
                            endpoint(link.source, port: link.sourcePort.resource, trailing: false).frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: 1) {
                                Text(link.label).font(.caption2.monospaced().bold()).foregroundStyle(SkyTheme.cyan).lineLimit(1)
                                Text("\(link.lineRate)  \(link.traffic)").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(minWidth: 180)
                            endpoint(link.target, port: link.targetPort.resource, trailing: true).frame(maxWidth: .infinity, alignment: .trailing)
                            Text(link.status).font(.caption2.monospaced().bold()).foregroundStyle(link.isUp ? SkyTheme.phosphor : SkyTheme.amber).frame(width: 48, alignment: .trailing)
                        }.padding(.horizontal, 9).frame(minHeight: 43).vintageInset(SkyTheme.inset)
                            .help("\(link.source.pretty_name) \(link.sourcePort.resource.pretty_name) ↔ \(link.target.pretty_name) \(link.targetPort.resource.pretty_name) · link changes \(link.linkChanges)")
                    }
                }
            }.padding(13).vintagePanel(SkyTheme.face)
        }
    }
    private func endpoint(_ device: SkyResource, port: SkyResource, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(device.pretty_name).font(.caption.bold()).lineLimit(1)
            Text(port.pretty_name).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct NetworkChassis: View {
    @EnvironmentObject var model: DashboardModel
    let projection: NetworkChassisProjection
    private var device: SkyResource { projection.device }
    private var ports: [SkyResource] { projection.ports.map(\.resource) }
    private var clients: [SkyResource] { projection.clients.map(\.resource) }
    private var state: [StateRow] { model.displayStatesByResource[device.id] ?? [] }
    private var health: String { projection.health.display == "—" ? device.availability : projection.health.display }
    private var facts: [StateRow] { Array(projection.facts.prefix(3)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: networkIcon)
                    .font(.title2).foregroundStyle(SkyTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.pretty_name).font(.title3.bold())
                    HStack(spacing: 8) {
                        Text(device.id).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        if !device.address.isEmpty { Text(device.address).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
                    }
                    if !device.comment.isEmpty { Text(device.comment).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(health.lowercased().capitalized).font(.caption.bold()).foregroundStyle(device.availability == "online" ? SkyTheme.phosphor : SkyTheme.amber)
                    MetadataButton(resource: device)
                }
            }
            if !facts.isEmpty {
                HStack(spacing: 16) { ForEach(facts) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.label ?? row.metric).font(.caption2).foregroundStyle(.secondary)
                        Text(row.display).font(.caption.monospaced()).lineLimit(1)
                    }
                } }
            }
            if !ports.isEmpty {
                Divider().overlay(SkyTheme.cyan.opacity(0.25))
                HStack { Text("Ports").font(.caption2.monospaced().bold()).foregroundStyle(SkyTheme.cyan); Spacer(); Text("\(ports.count) interfaces").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                SwitchPorts(device: device, ports: ports)
            }
            if !clients.isEmpty {
                Divider().overlay(SkyTheme.cyan.opacity(0.25))
                DisclosureGroup("Clients  \(clients.count)") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 7)], alignment: .leading, spacing: 7) {
                        ForEach(clients.sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending }) { client in
                            let rows = model.displayStatesByResource[client.id] ?? []
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.pretty_name).font(.caption.bold()).lineLimit(1)
                                Text(rows.first { $0.metric == "address" }?.display ?? "").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                Text([rows.first { $0.metric == "ssid" }?.display, rows.first { $0.metric == "signal" }?.display].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }.padding(6).vintageInset()
                        }
                    }.padding(.top, 7)
                }.font(.caption2.monospaced().bold()).foregroundStyle(SkyTheme.cyan)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
        .vintagePanel()
    }
    private var networkIcon: String {
        switch device.class {
        case "router": "network"
        case "access-point": "antenna.radiowaves.left.and.right"
        case "network-station": "cable.connector.horizontal"
        default: "point.3.connected.trianglepath.dotted"
        }
    }
}

struct ComputeTopology: View {
    @EnvironmentObject var model: DashboardModel
    let query: String
    private var sections: [(String, String)] {
        (model.presentationViews["compute"]?.sections ?? []).compactMap { section in
            guard let group = section.items.compactMap({ $0.query?.group }).first else { return nil }
            return (section.title, group)
        }
    }
    private struct TopologyRow: Identifiable {
        let resource: SkyResource
        let level: Int
        var id: String { resource.id }
    }
    private func members(_ group: String) -> [TopologyRow] {
        let earlier = Set(sections.prefix { $0.1 != group }.map { $0.1 })
        let values = model.resources.filter { resource in
            (resource.lifecycle == "active" || resource.lifecycle == "expected-offline") &&
            resource.presentation_home == "compute" && resource.groups.contains(group) && earlier.isDisjoint(with: resource.groups) &&
            (query.isEmpty || ([resource.pretty_name,resource.id,resource.comment] + resource.roles).joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
        let ids = Set(values.map(\.id))
        let byParent = Dictionary(grouping: values) { resource in
            guard let parent = resource.parent, ids.contains(parent) else { return "" }
            return parent
        }
        var rows: [TopologyRow] = []
        func append(_ resource: SkyResource, level: Int) {
            rows.append(TopologyRow(resource: resource, level: level))
            for child in (byParent[resource.id] ?? []).sorted(by: {
                if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
                return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
            }) {
                append(child, level: level + 1)
            }
        }
        for root in (byParent[""] ?? []).sorted(by: {
            if $0.availabilitySortRank != $1.availabilitySortRank { return $0.availabilitySortRank < $1.availabilitySortRank }
            return $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending
        }) { append(root, level: 0) }
        return rows
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(sections, id: \.1) { title, group in
                let values = members(group)
                if !values.isEmpty { ConsoleSection(title: title, subtitle: "resolved hosting topology") {
                    VStack(spacing: 8) { ForEach(values) { row in
                        HStack(alignment: .top, spacing: 8) {
                            if row.level > 0 { Text(String(repeating: "  ", count: min(row.level, 3)) + "└─").font(.body.monospaced()).foregroundStyle(SkyTheme.cyan.opacity(0.65)) }
                            ResourceCard(resource: row.resource, state: model.displayStatesByResource[row.resource.id] ?? [])
                        }
                    } }
                } }
            }
            let accessory = model.resources.filter { $0.lifecycle == "active" && $0.presentation_home == "compute" && Set($0.groups).isDisjoint(with: Set(sections.map { $0.1 })) }
            if !accessory.isEmpty { ConsoleSection(title: "Other Systems", subtitle: "active accessory compute") { ResourceGrid(resources: accessory) } }
        }
    }
}
