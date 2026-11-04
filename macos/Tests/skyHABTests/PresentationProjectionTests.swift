// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import skyHAB

private func resource(_ id: String, _ klass: String) throws -> SkyResource {
    let data = Data("""
    {"id":"\(id)","class":"\(klass)","adapter":"test","pretty_name":"\(id)","comment":"","room":"","groups":[],"roles":[],"lifecycle":"active","importance":"normal","presentation_home":"energy","children":[],"ancestors":[],"depth":0,"pinned":false,"address":"","availability":"online","severity":"info"}
    """.utf8)
    return try JSONDecoder().decode(SkyResource.self, from: data)
}

private func metric(_ resource: String, _ name: String, _ value: SkyValue, _ display: String) -> ProjectedMetric {
    ProjectedMetric(row: StateRow(resource: resource, metric: name, value: value, unit: "", quality: "good",
                                  observed_at_ms: 0, display_value: nil, display_unit: nil, display_decimals: nil,
                                  display_text: display, label: nil, display_priority: nil, visibility: nil,
                                  kind: nil, severity: nil, meaning: nil))
}

@Test func energyProjectionInterpretsSignedFlows() throws {
    let projection = EnergyFlowProjection(
        battery: try resource("battery", "battery-system"), solarGateway: nil,
        solar: metric("battery", "solar_power", .number(2_800), "2.8 kW"),
        house: metric("battery", "load_power", .number(1_600), "1.6 kW"),
        grid: metric("battery", "grid_power", .number(1_700), "1.7 kW"),
        batteryPower: metric("battery", "battery_power", .number(-2_700), "2.7 kW"),
        charge: metric("battery", "state_of_charge", .number(39), "39 %"),
        reserve: ProjectedMetric(row: nil), remaining: ProjectedMetric(row: nil),
        mode: ProjectedMetric(row: nil), gridConnected: ProjectedMetric(row: nil)
    )
    #expect(projection.gridDirection == "Importing")
    #expect(projection.batteryDirection == "Charging")
}

@Test func upsAndPortProjectionExposeOperationalState() throws {
    let ups = UPSProjection(resource: try resource("ups", "ups"),
                            status: metric("ups", "status", .string("OL"), "On line"),
                            charge: ProjectedMetric(row: nil), runtime: ProjectedMetric(row: nil),
                            load: ProjectedMetric(row: nil), realPower: ProjectedMetric(row: nil),
                            apparentPower: ProjectedMetric(row: nil), inputVoltage: ProjectedMetric(row: nil),
                            outputVoltage: ProjectedMetric(row: nil), temperature: ProjectedMetric(row: nil))
    let port = NetworkPortProjection(resource: try resource("switch/port/uplink", "network-port"),
                                     link: metric("switch/port/uplink", "link", .boolean(true), "Up"),
                                     lineRate: metric("switch/port/uplink", "line_rate", .string("10Gbps"), "10Gbps"),
                                     receiveRate: ProjectedMetric(row: nil), transmitRate: ProjectedMetric(row: nil),
                                     linkChanges: ProjectedMetric(row: nil))
    #expect(!ups.onBattery)
    #expect(ups.statusLabel == "On line")
    #expect(port.isUp)
    #expect(port.lineRate.display == "10Gbps")
}

@Test func storageProjectionPreservesServerCapacityPresentation() throws {
    let pool = try resource("storage-host/pool/main", "storage-pool")
    let projection = StorageCapacityProjection(resource: pool,
        health: metric(pool.id, "health", .string("ONLINE"), "ONLINE"),
        size: metric(pool.id, "size", .number(10_000), "10 TB"),
        allocated: metric(pool.id, "allocated", .number(6_200), "6.2 TB"),
        free: metric(pool.id, "free", .number(3_800), "3.8 TB"),
        utilization: metric(pool.id, "used_percent", .number(62), "62%"))
    #expect(projection.utilization.number == 62)
    #expect(projection.allocated.display == "6.2 TB")
}

@Test func liveFabricLinkRequiresBothEndpointLinks() throws {
    let source = try resource("source", "network-switch")
    let target = try resource("target", "network-switch")
    func port(_ id: String, up: Bool) throws -> NetworkPortProjection {
        NetworkPortProjection(resource: try resource(id, "network-port"),
                              link: metric(id, "link", .boolean(up), up ? "Up" : "Down"),
                              lineRate: metric(id, "line_rate", .string("10Gbps"), "10 Gbps"),
                              receiveRate: metric(id, "rx_rate", .number(1_000_000), "1.0 Mbps"),
                              transmitRate: metric(id, "tx_rate", .number(500_000), "500 kbps"),
                              linkChanges: metric(id, "link_downs", .number(2), "2"))
    }
    let relationship = SkyRelationship(id: "link", kind: "network-link", source: source.id, target: target.id,
                                       source_port: "uplink", target_port: "downlink", label: "Core trunk", capacity_bps: nil)
    let healthy = LiveNetworkLinkProjection(relationship: relationship, source: source, target: target,
                                            sourcePort: try port("source/port/uplink", up: true),
                                            targetPort: try port("target/port/downlink", up: true))
    let failed = LiveNetworkLinkProjection(relationship: relationship, source: source, target: target,
                                           sourcePort: try port("source/port/uplink", up: true),
                                           targetPort: try port("target/port/downlink", up: false))
    #expect(healthy.status == "Up")
    #expect(healthy.lineRate == "10 Gbps")
    #expect(failed.status == "Down")
}
