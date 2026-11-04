// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import Foundation

struct ProjectedMetric: Sendable {
    let row: StateRow?
    var display: String { row?.display ?? "—" }
    var number: Double? {
        guard let row else { return nil }
        if case .number(let value) = row.value { return value }
        return nil
    }
    var boolean: Bool? {
        guard let row else { return nil }
        if case .boolean(let value) = row.value { return value }
        return nil
    }
    var text: String? {
        guard let row else { return nil }
        if case .string(let value) = row.value { return value }
        return nil
    }
}

struct EnergyFlowProjection: Sendable {
    let battery: SkyResource
    let solarGateway: SkyResource?
    let solar: ProjectedMetric
    let house: ProjectedMetric
    let grid: ProjectedMetric
    let batteryPower: ProjectedMetric
    let charge: ProjectedMetric
    let reserve: ProjectedMetric
    let remaining: ProjectedMetric
    let mode: ProjectedMetric
    let gridConnected: ProjectedMetric

    var gridDirection: String {
        guard let watts = grid.number else { return "Unknown" }
        if watts > 50 { return "Importing" }
        if watts < -50 { return "Exporting" }
        return "Balanced"
    }
    var batteryDirection: String {
        guard let watts = batteryPower.number else { return "Unknown" }
        if watts > 50 { return "Discharging" }
        if watts < -50 { return "Charging" }
        return "Standby"
    }
    var gridConnectionLabel: String {
        guard let connected = gridConnected.boolean else { return "—" }
        return connected ? "Connected" : "Isolated"
    }
}

struct UPSProjection: Sendable {
    let resource: SkyResource
    let status: ProjectedMetric
    let charge: ProjectedMetric
    let runtime: ProjectedMetric
    let load: ProjectedMetric
    let realPower: ProjectedMetric
    let apparentPower: ProjectedMetric
    let inputVoltage: ProjectedMetric
    let outputVoltage: ProjectedMetric
    let temperature: ProjectedMetric

    var onBattery: Bool { status.text?.split(separator: " ").contains("OB") == true }
    var statusLabel: String {
        guard let value = status.text else { return "Unknown" }
        if value.split(separator: " ").contains("OB") { return "On battery" }
        if value.split(separator: " ").contains("OL") { return "On line" }
        return value
    }
}

struct NetworkPortProjection: Identifiable, Sendable {
    let resource: SkyResource
    let link: ProjectedMetric
    let lineRate: ProjectedMetric
    let receiveRate: ProjectedMetric
    let transmitRate: ProjectedMetric
    let linkChanges: ProjectedMetric
    var id: String { resource.id }
    var isUp: Bool { link.boolean == true }
}

struct NetworkClientProjection: Identifiable, Sendable {
    let resource: SkyResource
    let address: ProjectedMetric
    let ssid: ProjectedMetric
    let signal: ProjectedMetric
    let band: ProjectedMetric
    let bssid: ProjectedMetric
    var id: String { resource.id }
}

struct NetworkChassisProjection: Identifiable, Sendable {
    let device: SkyResource
    let health: ProjectedMetric
    let facts: [StateRow]
    let ports: [NetworkPortProjection]
    let clients: [NetworkClientProjection]
    var id: String { device.id }
}

struct LiveNetworkLinkProjection: Identifiable, Sendable {
    let relationship: SkyRelationship
    let source: SkyResource
    let target: SkyResource
    let sourcePort: NetworkPortProjection
    let targetPort: NetworkPortProjection
    var id: String { relationship.id }
    var label: String { relationship.label ?? relationship.kind.replacingOccurrences(of: "-", with: " ").capitalized }
    var status: String {
        if sourcePort.link.boolean == true && targetPort.link.boolean == true { return "Up" }
        if sourcePort.link.boolean == false || targetPort.link.boolean == false { return "Down" }
        return "Unknown"
    }
    var isUp: Bool { status == "Up" }
    var lineRate: String { sourcePort.lineRate.display != "—" ? sourcePort.lineRate.display : targetPort.lineRate.display }
    var traffic: String { "↓ \(sourcePort.receiveRate.display)  ↑ \(sourcePort.transmitRate.display)" }
    var linkChanges: String { sourcePort.linkChanges.display != "—" ? sourcePort.linkChanges.display : targetPort.linkChanges.display }
}

struct StorageCapacityProjection: Sendable {
    let resource: SkyResource
    let health: ProjectedMetric
    let size: ProjectedMetric
    let allocated: ProjectedMetric
    let free: ProjectedMetric
    let utilization: ProjectedMetric
}

struct MeshRadioProjection: Sendable {
    let role: ProjectedMetric
    let knownNodes: ProjectedMetric
    let recentNodes: ProjectedMetric
    let directNodes: ProjectedMetric
    let channelUtilization: ProjectedMetric
    let airUtilization: ProjectedMetric
    let latestActivity: ProjectedMetric
    let uptime: ProjectedMetric
    let firmware: ProjectedMetric
    let hardware: ProjectedMetric
    let localName: ProjectedMetric
    let localID: ProjectedMetric
}

extension DashboardModel {
    func meshRadioProjection(for resource: SkyResource) -> MeshRadioProjection {
        let state = displayStatesByResource[resource.id] ?? []
        func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: state.first { $0.metric == name }) }
        return MeshRadioProjection(role: metric("mesh_role"), knownNodes: metric("node_count"),
            recentNodes: metric("recent_node_count"), directNodes: metric("direct_node_count"),
            channelUtilization: metric("channel_utilization"), airUtilization: metric("air_utilization"),
            latestActivity: metric("last_mesh_activity_age"), uptime: metric("radio_uptime"),
            firmware: metric("firmware_version"), hardware: metric("hardware_model"),
            localName: metric("local_node_name"), localID: metric("local_node_id"))
    }

    func meaningfulRecentEvents(limit: Int = 12) -> [SkyStateEvent] {
        let metrics: Set<String> = ["health", "power", "brightness", "mode", "fan_mode", "partition_mode",
                                    "alarm", "fire", "trouble", "ready", "bypass", "state_of_charge", "grid_connected"]
        return Array(recentEvents.filter { metrics.contains($0.metric) }.prefix(limit))
    }

    func liveNetworkLinks(query: String = "") -> [LiveNetworkLinkProjection] {
        let byID = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })
        let allStates = displayStatesByResource
        return relationships.compactMap { link in
            guard link.kind == "network-link", let sourcePortID = link.source_port, let targetPortID = link.target_port,
                  let source = byID[link.source], let target = byID[link.target],
                  let sourcePortResource = byID[link.source + "/port/" + sourcePortID],
                  let targetPortResource = byID[link.target + "/port/" + targetPortID] else { return nil }
            func port(_ resource: SkyResource) -> NetworkPortProjection {
                let state = allStates[resource.id] ?? []
                func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: state.first { $0.metric == name }) }
                return NetworkPortProjection(resource: resource, link: metric("link"), lineRate: metric("line_rate"),
                                             receiveRate: metric("rx_rate"), transmitRate: metric("tx_rate"),
                                             linkChanges: metric("link_downs"))
            }
            let projection = LiveNetworkLinkProjection(relationship: link, source: source, target: target,
                                                       sourcePort: port(sourcePortResource), targetPort: port(targetPortResource))
            guard query.isEmpty || [source.pretty_name, source.id, sourcePortResource.pretty_name, sourcePortID,
                                    target.pretty_name, target.id, targetPortResource.pretty_name, targetPortID, projection.label]
                .joined(separator: " ").localizedCaseInsensitiveContains(query) else { return nil }
            return projection
        }
    }

    func energyFlowProjection() -> EnergyFlowProjection? {
        let resources = presentationResources(viewID: "energy", sectionID: "flow")
        guard let battery = resources.first(where: { $0.class == "battery-system" })
                ?? self.resources.first(where: { $0.class == "battery-system" }) else { return nil }
        let gateway = resources.first(where: { $0.class == "solar-gateway" })
            ?? self.resources.first(where: { $0.class == "solar-gateway" })
        let batteryState = displayStatesByResource[battery.id] ?? []
        let gatewayState = gateway.map { source in displayStatesByResource[source.id] ?? [] } ?? []
        func batteryMetric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: batteryState.first { $0.metric == name }) }
        let batterySolar = batteryMetric("solar_power")
        let gatewaySolar = ProjectedMetric(row: gatewayState.first { $0.metric == "production_power" })
        return EnergyFlowProjection(
            battery: battery, solarGateway: gateway,
            solar: batterySolar.row == nil ? gatewaySolar : batterySolar,
            house: batteryMetric("load_power"), grid: batteryMetric("grid_power"),
            batteryPower: batteryMetric("battery_power"), charge: batteryMetric("state_of_charge"),
            reserve: batteryMetric("backup_reserve"), remaining: batteryMetric("energy_remaining"),
            mode: batteryMetric("mode"), gridConnected: batteryMetric("grid_connected")
        )
    }

    func upsProjection() -> UPSProjection? {
        let candidates = presentationResources(viewID: "energy", sectionID: "protection")
        guard let resource = candidates.first(where: { $0.class == "ups" })
                ?? resources.first(where: { $0.class == "ups" }) else { return nil }
        let rows = displayStatesByResource[resource.id] ?? []
        func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: rows.first { $0.metric == name }) }
        return UPSProjection(resource: resource, status: metric("status"), charge: metric("battery_charge"),
                             runtime: metric("battery_runtime"), load: metric("load"), realPower: metric("real_power"),
                             apparentPower: metric("apparent_power"), inputVoltage: metric("input_voltage"),
                             outputVoltage: metric("output_voltage"), temperature: metric("temperature"))
    }

    func networkChassisProjections(query: String = "") -> [NetworkChassisProjection] {
        let classes = Set(["router", "network-switch", "network-station", "access-point"])
        var seen = Set<String>()
        let devices = presentationSections(for: "network").flatMap(\.1).filter {
            classes.contains($0.class) && seen.insert($0.id).inserted
        }
        let projected = devices.map { device in
            let rows = displayStatesByResource[device.id] ?? []
            let facts = Array(rows.filter { $0.visibility == "summary" && $0.metric != "health" && $0.metric != "management_access" }
                .sorted { ($0.display_priority ?? 50) < ($1.display_priority ?? 50) }.prefix(4))
            let ports = resources.filter { $0.parent == device.id && $0.class == "network-port" }
                .sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending }
                .map { port -> NetworkPortProjection in
                    let state = displayStatesByResource[port.id] ?? []
                    func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: state.first { $0.metric == name }) }
                    return NetworkPortProjection(resource: port, link: metric("link"), lineRate: metric("line_rate"),
                                                 receiveRate: metric("rx_rate"), transmitRate: metric("tx_rate"),
                                                 linkChanges: metric("link_downs"))
                }
            let clients = resources.filter { $0.parent == device.id && $0.class == "network-client" }
                .sorted { $0.pretty_name.localizedStandardCompare($1.pretty_name) == .orderedAscending }
                .map { client -> NetworkClientProjection in
                    let state = displayStatesByResource[client.id] ?? []
                    func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: state.first { $0.metric == name }) }
                    return NetworkClientProjection(resource: client, address: metric("address"), ssid: metric("ssid"),
                                                   signal: metric("signal"), band: metric("band"), bssid: metric("bssid"))
                }
            return NetworkChassisProjection(device: device, health: ProjectedMetric(row: rows.first { $0.metric == "health" }),
                                            facts: facts, ports: ports, clients: clients)
        }
        guard !query.isEmpty else { return projected }
        return projected.filter { chassis in
            ([chassis.device.pretty_name, chassis.device.id, chassis.device.address, chassis.device.comment]
             + chassis.ports.flatMap { [$0.resource.pretty_name, $0.resource.id] }
             + chassis.clients.flatMap { [$0.resource.pretty_name, $0.resource.id, $0.address.display] })
                .joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    func storageCapacityProjection(for resource: SkyResource) -> StorageCapacityProjection {
        let rows = displayStatesByResource[resource.id] ?? []
        func metric(_ name: String) -> ProjectedMetric { ProjectedMetric(row: rows.first { $0.metric == name }) }
        return StorageCapacityProjection(resource: resource, health: metric("health"), size: metric("size"),
                                         allocated: metric("allocated"), free: metric("free"),
                                         utilization: metric("used_percent"))
    }
}
