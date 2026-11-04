// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import Foundation
import SwiftUI

enum AssetPhotoUpdate: Sendable {
    case unchanged
    case set(Data, mime: String)
    case delete
}

@MainActor
final class DashboardModel: ObservableObject {
    @Published var resources: [SkyResource] = []
    @Published var states: [StateRow] = [] { didSet { displayStatesByResourceCache = nil } }
    @Published var views: [SkyViewSummary] = []
    @Published var relationships: [SkyRelationship] = []
    @Published var recentEvents: [SkyStateEvent] = []
    @Published var presentationViews: [String: SkyPresentationView] = [:]
    @Published var connected = false
    @Published var error = ""
    @Published var energyHistory: [EnergyChartPoint] = []
    @Published var airQualityHistory: [EnergyChartPoint] = []
    @Published var serverEndpoint = "Not configured"
    @Published var serverIdentity = "Not connected"
    @Published var siteName = "Local site"
    @Published var siteSubtitle = "Local-first habitat console"
    @Published private(set) var assetPhotos: [String: Data] = [:]
    @Published private(set) var storageFileListings: [String: SkyStorageFileListing] = [:]
    @Published private(set) var storageFilesLoading: Set<String> = []
    @Published private var pendingControls: [String: PendingControl] = [:] { didSet { displayStatesByResourceCache = nil } }
    var unreachable: Int { states.filter { $0.metric == "health" && $0.value.string == "unreachable" }.count }
    var displayStates: [StateRow] {
        var output = states
        for (resource, control) in pendingControls {
            for change in control.changes {
                if let index = output.firstIndex(where: { $0.resource == resource && $0.metric == change.metric }) {
                    output[index] = output[index].replacing(value: change.value, displayText: change.displayText)
                }
            }
        }
        return output
    }
    private var client: SkyWireClient?
    private var configuredHost: String?
    private var configuredPort: UInt16?
    private var configuredToken: String?
    private var configuredClientName: String?
    private var presentationRevision: UInt64?
    private var nextControlGeneration: UInt64 = 1
    private var lastHistoryRefresh: Date?
    private var refreshInProgress = false
    private var lastInventoryRevision: UInt64?
    private var suspended = false
    private var displayStatesByResourceCache: [String: [StateRow]]?

    // Row lookups by resource are O(n) scans of the full state array on every
    // card, port, and client render. Build the index once per state change.
    var displayStatesByResource: [String: [StateRow]] {
        if let displayStatesByResourceCache { return displayStatesByResourceCache }
        var index: [String: [StateRow]] = [:]
        for row in displayStates { index[row.resource, default: []].append(row) }
        displayStatesByResourceCache = index
        return index
    }

    private struct PendingChange {
        let metric: String
        let value: SkyValue
        let displayText: String?
    }
    private struct PendingControl {
        let generation: UInt64
        let changes: [PendingChange]
    }

    func configure(host: String, port: UInt16, token: String, clientName: String) {
        guard host != configuredHost || port != configuredPort || token != configuredToken || clientName != configuredClientName else { return }
        client = nil
        configuredHost = host
        configuredPort = port
        configuredToken = token
        configuredClientName = clientName
        serverEndpoint = "\(host):\(port)"
    }

    func run() async {
        while !Task.isCancelled {
            if suspended { try? await Task.sleep(for: .seconds(1)); continue }
            await refresh()
            try? await Task.sleep(for: .seconds(5))
        }
    }

    // Background the 5 s tick when the scene is not visible; saves radio and
    // battery on iOS without touching the serialized connection itself.
    func suspendPolling() { suspended = true }
    func resumePolling() { suspended = false }

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        do {
            let bundled = SkyClientConfiguration.load()
            let host = configuredHost ?? bundled.host
            let port = configuredPort ?? bundled.port
            let environment = ProcessInfo.processInfo.environment
            let token = configuredToken ?? KeychainToken.load() ?? environment["SKYHAB_TOKEN"] ?? environment["SKYLAB_TOKEN"] ?? ""
            let clientName = configuredClientName ?? bundled.client
            guard !token.isEmpty else { throw SkyWireError.server("A SkyWire token is required") }
            serverEndpoint = "\(host):\(port)"
            let client = self.client ?? SkyWireClient(host: host, port: port, token: token, clientName: clientName)
            if self.client == nil { try await client.connect(); self.client = client }
            let service = try await client.serviceDescription()
            serverIdentity = "\(service.name) \(service.version) · \(service.protocol)"
            siteName = service.site?.pretty_name ?? "Local site"
            siteSubtitle = service.site?.subtitle ?? "Local-first habitat console"
            // State first: the console paints as soon as the authoritative snapshot
            // lands, and the bulkier inventory/view/history fetches follow.
            states = try await client.state()
            if lastInventoryRevision != service.inventory_revision || resources.isEmpty {
                resources = try await client.resources()
                relationships = try await client.relationships()
                lastInventoryRevision = service.inventory_revision
            }
            recentEvents = try await client.events()
            if presentationRevision != service.view_revision || presentationViews.isEmpty {
                views = try await client.views().sorted { $0.priority < $1.priority }
                var described: [String: SkyPresentationView] = [:]
                for summary in views { described[summary.id] = try await client.view(id: summary.id) }
                presentationViews = described
                presentationRevision = service.view_revision
            }
            connected = true
            error = ""
            scheduleHistoryRefresh(host: host, port: port, token: token, clientName: clientName)
        } catch {
            connected = false
            if let client { await client.disconnect() }
            self.client = nil
            self.error = String(describing: error)
        }
    }

    // History maintenance must never occupy the serialized operational connection
    // used by state refreshes, controls, and camera discovery. Authentication binds
    // tokens to an exact client identity. Multiple connections are supported, but
    // each must present that same identity. It also runs detached from refresh():
    // a cold start paints live state immediately instead of waiting on seven
    // metric queries, and a slow history fetch cannot stretch the 5 s tick.
    private func scheduleHistoryRefresh(host: String, port: UInt16, token: String, clientName: String) {
        let now = Date()
        if let lastHistoryRefresh, now.timeIntervalSince(lastHistoryRefresh) < 60 { return }
        lastHistoryRefresh = now
        Task {
            let since = now.addingTimeInterval(-24 * 60 * 60)
            let historyClient = SkyWireClient(host: host, port: port, token: token, clientName: clientName)
            do {
                try await historyClient.connect()
                func samples(_ resource: String?, _ metric: String) async -> [MetricPoint] {
                    guard let resource else { return [] }
                    return (try? await historyClient.metric(resource: resource, metric: metric, since: since)) ?? []
                }
                let powerSources = presentationResources(viewID: "overview", sectionID: "power")
                let solarID = powerSources.first { $0.class == "solar-gateway" }?.id
                let batteryID = powerSources.first { $0.class == "battery-system" }?.id
                let solar = await samples(solarID, "production_power")
                let soc = await samples(batteryID, "state_of_charge")
                energyHistory = solar.compactMap { EnergyChartPoint(point: $0, series: "Solar Production", unit: "W") }
                    + soc.compactMap { EnergyChartPoint(point: $0, series: "Battery Charge", unit: "%") }

                let airSource = presentationResources(viewID: "overview", sectionID: "air-quality").first?.id
                let pm25 = await samples(airSource, "pm2_5")
                let pm10 = await samples(airSource, "pm10")
                let formaldehyde = await samples(airSource, "formaldehyde")
                let voc = await samples(airSource, "voc_index")
                let no2 = await samples(airSource, "no2_index")
                airQualityHistory = pm25.compactMap { EnergyChartPoint(point: $0, series: "PM2.5", unit: "µg/m³") }
                    + pm10.compactMap { EnergyChartPoint(point: $0, series: "PM10", unit: "µg/m³") }
                    + formaldehyde.compactMap { EnergyChartPoint(point: $0, series: "Formaldehyde", unit: "µg/m³") }
                    + voc.compactMap { EnergyChartPoint(point: $0, series: "VOC", unit: "index") }
                    + no2.compactMap { EnergyChartPoint(point: $0, series: "NO₂", unit: "index") }
                await historyClient.disconnect()
            } catch {
                // Live state remains valid when optional history is unavailable.
                await historyClient.disconnect()
            }
        }
    }

    func presentationSections(for viewID: String, query: String = "") -> [(SkyPresentationSection, [SkyResource])] {
        guard let view = presentationViews[viewID] else { return [] }
        return view.sections.sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }.map { section in
            var seen = Set<String>()
            var values: [SkyResource] = []
            for item in section.items {
                let matches: [SkyResource]
                if let id = item.resource, let resource = resources.first(where: { $0.id == id }) { matches = [resource] }
                else if let selector = item.query { matches = orderedForPresentation(resources.filter { selector.matches($0) }) }
                else { matches = orderedForPresentation(resources) }
                for resource in matches where item.include_embedded || !["network-port", "network-client", "storage-disk", "storage-vdev"].contains(resource.class) {
                    if seen.insert(resource.id).inserted { values.append(resource) }
                }
            }
            values = values.filter { query.isEmpty || ([$0.pretty_name, $0.id, $0.address, $0.room] + $0.groups + $0.roles).joined(separator: " ").localizedCaseInsensitiveContains(query) }
            return (section, values)
        }
    }

    func presentationResources(viewID: String, sectionID: String) -> [SkyResource] {
        presentationSections(for: viewID).first { $0.0.id == sectionID }?.1 ?? []
    }

    func overviewResources(query: String = "") -> (habitat: [SkyResource], infrastructure: [SkyResource], pinned: [SkyResource], review: [SkyResource]) {
        let active = resources.filter { $0.lifecycle == "active" && !["network-port", "storage-disk", "storage-vdev"].contains($0.class) }
        func matching(_ values: [SkyResource]) -> [SkyResource] {
            guard !query.isEmpty else { return values }
            return values.filter { ([$0.pretty_name, $0.id, $0.comment] + $0.roles + $0.groups).joined(separator: " ").localizedCaseInsensitiveContains(query) }
        }
        let infrastructure = active.filter {
            $0.importance == "critical" && ($0.groups.contains("core-networking") ||
                $0.groups.contains("core-infrastructure") || ["ups", "hyperconverged-host"].contains($0.class))
        }
        let infrastructureIDs = Set(infrastructure.map(\.id))
        let habitat = active.filter { $0.importance == "critical" && !infrastructureIDs.contains($0.id) && ($0.groups.contains("core-habitat") || $0.groups.contains("core-power")) }
        let shown = Set((habitat + infrastructure).map(\.id))
        let pinned = active.filter { $0.pinned && !shown.contains($0.id) }
        let review = active.filter { ($0.importance == "critical" || $0.importance == "important") && ($0.availability == "offline" || $0.severity == "critical" || $0.severity == "warning") }
        return (matching(habitat), matching(infrastructure), matching(pinned), matching(review))
    }

    private func orderedForPresentation(_ input: [SkyResource]) -> [SkyResource] {
        let ids = Set(input.map(\.id))
        let children = Dictionary(grouping: input.filter { $0.parent.map(ids.contains) == true }, by: { $0.parent! })
        let roots = input.filter { $0.parent.map(ids.contains) != true }
        func siblingOrder(_ left: SkyResource, _ right: SkyResource) -> Bool {
            if left.pinned != right.pinned { return left.pinned }
            if (left.pin_order ?? Int.max) != (right.pin_order ?? Int.max) { return (left.pin_order ?? Int.max) < (right.pin_order ?? Int.max) }
            if left.availabilitySortRank != right.availabilitySortRank { return left.availabilitySortRank < right.availabilitySortRank }
            return left.pretty_name.localizedStandardCompare(right.pretty_name) == .orderedAscending
        }
        var output: [SkyResource] = []
        func appendTree(_ resource: SkyResource) {
            output.append(resource)
            for child in (children[resource.id] ?? []).sorted(by: siblingOrder) { appendTree(child) }
        }
        for root in roots.sorted(by: siblingOrder) { appendTree(root) }
        return output
    }

    func invoke(_ resource: SkyResource, action: String, parameters: [String: String] = [:]) async {
        guard let client else { error = "Not connected"; return }
        let generation = nextControlGeneration
        nextControlGeneration += 1
        let changes = desiredChanges(action: action, parameters: parameters)
        if !changes.isEmpty { pendingControls[resource.id] = PendingControl(generation: generation, changes: changes) }
        do {
            try await client.invoke(resource: resource.id, action: action, parameters: parameters)
            states = try await client.state()
            if pendingControls[resource.id]?.generation == generation { pendingControls.removeValue(forKey: resource.id) }
            connected = true
            error = ""
        } catch {
            if pendingControls[resource.id]?.generation == generation { pendingControls.removeValue(forKey: resource.id) }
            await client.disconnect()
            if self.client === client { self.client = nil }
            connected = false
            self.error = String(describing: error)
        }
    }

    func isControlPending(_ resource: String) -> Bool { pendingControls[resource] != nil }

    private func desiredChanges(action: String, parameters: [String: String]) -> [PendingChange] {
        var changes: [PendingChange] = []
        switch action {
        case "power.on": changes = [PendingChange(metric: "power", value: .boolean(true), displayText: "On")]
        case "power.off": changes = [PendingChange(metric: "power", value: .boolean(false), displayText: "Off")]
        case "brightness.set":
            if let text = parameters["brightness"], let value = Double(text) {
                // Brightness intent does not predict relay state. Preserve the last
                // authoritative power observation until post-action readback arrives.
                changes = [PendingChange(metric: "brightness", value: .number(value), displayText: nil)]
            }
        case "thermostat.mode.set":
            if let mode = parameters["mode"] { changes = [PendingChange(metric: "mode", value: .string(mode), displayText: mode)] }
        case "thermostat.fan.set":
            if let fan = parameters["fan"] { changes = [PendingChange(metric: "fan_mode", value: .string(fan), displayText: fan)] }
        case "thermostat.setpoints.set":
            if let text = parameters["heat"], let value = Double(text) { changes.append(PendingChange(metric: "heat_setpoint", value: .number(value), displayText: nil)) }
            if let text = parameters["cool"], let value = Double(text) { changes.append(PendingChange(metric: "cool_setpoint", value: .number(value), displayText: nil)) }
        case "dyson.fan_speed.set":
            if let text = parameters["speed"], let value = Double(text) { changes = [PendingChange(metric: "fan_speed", value: .number(value), displayText: nil)] }
        case "dyson.auto.set": changes = [PendingChange(metric: "auto_mode", value: .boolean(parameters["enabled"] == "true"), displayText: nil)]
        case "dyson.night.set": changes = [PendingChange(metric: "night_mode", value: .boolean(parameters["enabled"] == "true"), displayText: nil)]
        case "dyson.oscillation.set": changes = [PendingChange(metric: "oscillation", value: .boolean(parameters["enabled"] == "true"), displayText: nil)]
        default: break
        }
        return changes
    }

    func setPinned(_ resource: SkyResource, _ pinned: Bool) async {
        do { try await client?.setPinned(resource: resource.id, pinned: pinned); await refresh() }
        catch { self.error = String(describing: error) }
    }

    func cameraStream(_ resource: SkyResource) async throws -> String {
        for attempt in 0..<2 {
            if client == nil { await refresh() }
            guard let activeClient = client else { throw SkyWireError.disconnected }
            do {
                return try await activeClient.cameraStreamURL(resource: resource.id)
            } catch {
                await activeClient.disconnect()
                if client === activeClient { client = nil }
                connected = false
                if attempt == 1 { throw error }
            }
        }
        throw SkyWireError.disconnected
    }

    func cameraURL(_ resource: SkyResource) async throws -> URL {
        let text = try await cameraStream(resource)
        guard let url = URL(string: text) else { throw SkyWireError.malformed("invalid camera stream URL") }
        return url
    }

    func loadAssetPhoto(_ resource: SkyResource, force: Bool = false) async -> Data? {
        guard resource.photo_available else { assetPhotos[resource.id] = nil; return nil }
        if !force, let cached = assetPhotos[resource.id] { return cached }
        guard let client else { return nil }
        do {
            let photo = try await client.assetPhoto(resource: resource.id)
            assetPhotos[resource.id] = photo.data
            return photo.data
        } catch {
            self.error = String(describing: error)
            return nil
        }
    }

    func loadStorageFiles(_ resource: SkyResource, force: Bool = false) async {
        if !force, storageFileListings[resource.id] != nil { return }
        guard !storageFilesLoading.contains(resource.id) else { return }
        storageFilesLoading.insert(resource.id); defer { storageFilesLoading.remove(resource.id) }
        let bundled = SkyClientConfiguration.load()
        let host = configuredHost ?? bundled.host
        let port = configuredPort ?? bundled.port
        let environment = ProcessInfo.processInfo.environment
        let token = configuredToken ?? KeychainToken.load() ?? environment["SKYHAB_TOKEN"] ?? environment["SKYLAB_TOKEN"] ?? ""
        let clientName = configuredClientName ?? bundled.client
        guard !token.isEmpty else { error = "A SkyWire token is required"; return }
        // RouterOS directory enumeration may take seconds. Keep it off the serialized
        // operational connection used by polling, controls, and camera discovery.
        let detailClient = SkyWireClient(host: host, port: port, token: token, clientName: clientName)
        do {
            try await detailClient.connect()
            storageFileListings[resource.id] = try await detailClient.storageFiles(resource: resource.id)
            error = ""
        } catch { self.error = String(describing: error) }
        await detailClient.disconnect()
    }

    func edit(_ resource: SkyResource, name: String, room: String, groups: [String], comment: String,
              assetTag: String, notes: String, photo: AssetPhotoUpdate = .unchanged) async -> Bool {
        guard let client else { error = "Not connected"; return false }
        for attempt in 0..<2 {
            do {
                var revision = try await client.inventoryRevision()
                let changes: [String: Any] = ["pretty_name": name, "room": room, "groups": groups, "comment": comment,
                                              "asset_tag": assetTag, "notes": notes]
                try await client.patchMetadata(resource: resource.id, revision: revision, changes: changes)
                revision = try await client.inventoryRevision()
                switch photo {
                case .unchanged: break
                case .set(let data, let mime):
                    try await client.setAssetPhoto(resource: resource.id, revision: revision, mime: mime, data: data)
                    assetPhotos[resource.id] = data
                case .delete:
                    if resource.photo_available { try await client.deleteAssetPhoto(resource: resource.id, revision: revision) }
                    assetPhotos[resource.id] = nil
                }
                let updated = try await client.resources()
                guard let saved = updated.first(where: { $0.id == resource.id }), saved.pretty_name == name,
                      saved.room == room, saved.groups == groups, saved.comment == comment,
                      saved.asset_tag == assetTag, saved.notes == notes else {
                    throw SkyWireError.server("The server did not return the saved metadata for \(resource.id)")
                }
                resources = updated
                error = ""
                return true
            } catch {
                self.error = String(describing: error)
                if attempt == 1 { return false }
            }
        }
        return false
    }

    func edit(_ resource: SkyResource, name: String, room: String, groups: [String], comment: String) async -> Bool {
        await edit(resource, name: name, room: room, groups: groups, comment: comment,
                   assetTag: resource.asset_tag, notes: resource.notes)
    }
}

private extension SkyPresentationQuery {
    func matches(_ resource: SkyResource) -> Bool {
        if let `class`, resource.class != `class` { return false }
        if let pinned, resource.pinned != pinned { return false }
        if let group, !resource.groups.contains(group) { return false }
        if let presentation_home, resource.presentation_home != presentation_home { return false }
        if let lifecycle, !lifecycle.contains(resource.lifecycle) { return false }
        if let severity, !severity.contains(resource.severity) { return false }
        if let availability, resource.availability != availability { return false }
        if exclude_classes.contains(resource.class) { return false }
        if !Set(exclude_groups).isDisjoint(with: resource.groups) { return false }
        return true
    }
}

struct EnergyChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String
    let unit: String
    init?(point: MetricPoint, series: String, unit: String) {
        guard case .number(let value) = point.value else { return nil }
        date = Date(timeIntervalSince1970: Double(point.observed_at_ms) / 1000)
        self.value = value
        self.series = series
        self.unit = unit
    }
}
