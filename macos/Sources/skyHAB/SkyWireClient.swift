// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import Foundation
import Network

enum KeychainToken {
    static func load() -> String? {
        if let bundled = Bundle.main.url(forResource: "app", withExtension: "token"),
           let value = try? String(contentsOf: bundled, encoding: .utf8) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #if os(macOS)
        for directory in ["skyHAB", "skyLAB"] {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(directory)/app.token")
            if let value = try? String(contentsOf: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
        #else
        return nil
        #endif
    }
}

struct SkyClientConfiguration: Decodable {
    let host: String
    let port: UInt16
    let client: String
    static func load() -> SkyClientConfiguration {
        if let bundled = Bundle.main.url(forResource: "client", withExtension: "json"),
           let data = try? Data(contentsOf: bundled),
           let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        #if os(macOS)
        for directory in ["skyHAB", "skyLAB"] {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(directory)/client.json")
            if let data = try? Data(contentsOf: path),
               let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        }
        #endif
        return Self(host: "127.0.0.1", port: 3636, client: "skyHAB.macos")
    }
}

enum SkyWireError: Error {
    case disconnected
    case timeout(String)
    case malformed(String)
    case server(String)
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

struct SkyViewSummary: Identifiable, Decodable, Sendable {
    let id: String
    let title: String
    let icon: String
    let priority: Int
}

struct SkyPresentationView: Identifiable, Decodable, Sendable {
    let id: String
    let title: String
    let icon: String
    let priority: Int
    let sections: [SkyPresentationSection]
}

struct SkyPresentationSection: Identifiable, Decodable, Sendable {
    let id: String
    let title: String
    let priority: Int
    let layout: String
    let items: [SkyPresentationItem]
    enum CodingKeys: String, CodingKey { case id, title, priority, layout, items }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        priority = try values.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        layout = try values.decodeIfPresent(String.self, forKey: .layout) ?? "list"
        items = try values.decodeIfPresent([SkyPresentationItem].self, forKey: .items) ?? []
    }
}

struct SkyPresentationItem: Decodable, Sendable {
    let resource: String?
    let query: SkyPresentationQuery?
    let renderer: String
    let include_embedded: Bool
    enum CodingKeys: String, CodingKey { case resource, query, renderer, include_embedded }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        resource = try values.decodeIfPresent(String.self, forKey: .resource)
        query = try values.decodeIfPresent(SkyPresentationQuery.self, forKey: .query)
        renderer = try values.decodeIfPresent(String.self, forKey: .renderer) ?? "resource-row"
        include_embedded = try values.decodeIfPresent(Bool.self, forKey: .include_embedded) ?? false
    }
}

struct SkyPresentationQuery: Decodable, Sendable {
    let `class`: String?
    let pinned: Bool?
    let group: String?
    let presentation_home: String?
    let lifecycle: [String]?
    let severity: [String]?
    let availability: String?
    let exclude_classes: [String]
    let exclude_groups: [String]
    enum CodingKeys: String, CodingKey { case `class`, pinned, group, presentation_home, lifecycle, severity, availability, exclude_classes, exclude_groups }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        `class` = try values.decodeIfPresent(String.self, forKey: .class)
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned)
        group = try values.decodeIfPresent(String.self, forKey: .group)
        presentation_home = try values.decodeIfPresent(String.self, forKey: .presentation_home)
        lifecycle = try Self.stringList(values, .lifecycle)
        severity = try Self.stringList(values, .severity)
        availability = try values.decodeIfPresent(String.self, forKey: .availability)
        exclude_classes = try values.decodeIfPresent([String].self, forKey: .exclude_classes) ?? []
        exclude_groups = try values.decodeIfPresent([String].self, forKey: .exclude_groups) ?? []
    }
    private static func stringList(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [String]? {
        if let list = try? values.decodeIfPresent([String].self, forKey: key) { return list }
        if let value = try values.decodeIfPresent(String.self, forKey: key) { return [value] }
        return nil
    }
}

struct SkyServiceDescription: Decodable, Sendable {
    let name: String
    let version: String
    let `protocol`: String
    let inventory_revision: UInt64
    let view_revision: UInt64
    let site: SkySiteDescription?
}

struct SkySiteDescription: Decodable, Sendable {
    let id: String
    let pretty_name: String
    let subtitle: String
    let timezone: String
}

struct SkyResource: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let `class`: String
    let adapter: String
    let pretty_name: String
    let comment: String
    let asset_tag: String
    let notes: String
    let photo_available: Bool
    let parent: String?
    let room: String
    let groups: [String]
    let roles: [String]
    let lifecycle: String
    let importance: String
    let presentation_home: String
    let children: [String]
    let ancestors: [String]
    let depth: Int
    let pinned: Bool
    let pin_order: Int?
    let address: String
    let availability: String
    let severity: String

    var availabilitySortRank: Int { availability == "offline" ? 2 : availability == "unknown" ? 1 : 0 }

    enum CodingKeys: String, CodingKey { case id, `class`, adapter, pretty_name, comment, asset_tag, notes, photo_available, parent, room, groups, roles, lifecycle, importance, presentation_home, children, ancestors, depth, pinned, pin_order, address, availability, severity }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        `class` = try values.decode(String.self, forKey: .class)
        adapter = try values.decode(String.self, forKey: .adapter)
        pretty_name = try values.decode(String.self, forKey: .pretty_name)
        comment = try values.decode(String.self, forKey: .comment)
        asset_tag = try values.decodeIfPresent(String.self, forKey: .asset_tag) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photo_available = try values.decodeIfPresent(Bool.self, forKey: .photo_available) ?? false
        parent = try values.decodeIfPresent(String.self, forKey: .parent)
        room = try values.decodeIfPresent(String.self, forKey: .room) ?? ""
        groups = try values.decodeIfPresent([String].self, forKey: .groups) ?? []
        roles = try values.decodeIfPresent([String].self, forKey: .roles) ?? []
        lifecycle = try values.decodeIfPresent(String.self, forKey: .lifecycle) ?? "active"
        importance = try values.decodeIfPresent(String.self, forKey: .importance) ?? "normal"
        presentation_home = try values.decodeIfPresent(String.self, forKey: .presentation_home) ?? "inventory"
        children = try values.decodeIfPresent([String].self, forKey: .children) ?? []
        ancestors = try values.decodeIfPresent([String].self, forKey: .ancestors) ?? []
        depth = try values.decodeIfPresent(Int.self, forKey: .depth) ?? 0
        pinned = try values.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        pin_order = try values.decodeIfPresent(Int.self, forKey: .pin_order)
        address = try values.decodeIfPresent(String.self, forKey: .address) ?? ""
        availability = try values.decodeIfPresent(String.self, forKey: .availability) ?? "unknown"
        severity = try values.decodeIfPresent(String.self, forKey: .severity) ?? "info"
    }
}

struct SkyAssetPhoto: Sendable {
    let data: Data
    let mime: String
}

struct SkyRelationship: Identifiable, Decodable, Hashable, Sendable {
    let id: String
    let kind: String
    let source: String
    let target: String
    let source_port: String?
    let target_port: String?
    let label: String?
    let capacity_bps: UInt64?
}

struct SkyStorageFile: Identifiable, Decodable, Sendable {
    let path: String
    let name: String
    let modified: String
    let modified_at_ms: Int64
    let age: String
    let size_bytes: Double?
    let display_size: String?
    var id: String { path }
}

struct SkyStorageFileListing: Decodable, Sendable {
    let resource: String
    let available: Bool
    let message: String
    let files: [SkyStorageFile]
}

struct SkyStateEvent: Identifiable, Decodable, Sendable {
    let sequence: Int64
    let observed_at_ms: Int64
    let resource: String
    let metric: String
    let old_value: SkyValue
    let new_value: SkyValue
    var id: Int64 { sequence }
}

enum SkyValue: Codable, Sendable, CustomStringConvertible {
    case string(String), number(Double), boolean(Bool), null
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .boolean(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else { self = .string(try value.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self { case .string(let v): try value.encode(v); case .number(let v): try value.encode(v); case .boolean(let v): try value.encode(v); case .null: try value.encodeNil() }
    }
    var description: String { switch self { case .string(let v): v; case .number(let v): v.formatted(); case .boolean(let v): v ? "on" : "off"; case .null: "—" } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
}

struct StateRow: Codable, Sendable, Identifiable {
    var id: String { resource + ":" + metric }
    let resource: String
    let metric: String
    let value: SkyValue
    let unit: String
    let quality: String
    let observed_at_ms: Int64
    let display_value: SkyValue?
    let display_unit: String?
    let display_decimals: Int?
    let display_text: String?
    let label: String?
    let display_priority: Int?
    let visibility: String?
    let kind: String?
    let severity: String?
    let meaning: String?

    var display: String {
        if let display_text { return display_text }
        let value = display_value ?? self.value
        let unit = display_unit ?? self.unit
        let text: String
        if case .number(let number) = value {
            text = number.formatted(.number.precision(.fractionLength(display_decimals ?? 1)))
        } else { text = value.description }
        return text + (unit.isEmpty ? "" : " " + unit)
    }

    func replacing(value: SkyValue, displayText: String? = nil) -> StateRow {
        StateRow(resource: resource, metric: metric, value: value, unit: unit, quality: "optimistic",
                 observed_at_ms: Int64(Date().timeIntervalSince1970 * 1000), display_value: value,
                 display_unit: display_unit, display_decimals: display_decimals, display_text: displayText,
                 label: label, display_priority: display_priority, visibility: visibility, kind: kind,
                 severity: severity, meaning: displayText ?? meaning)
    }
}

struct MetricPoint: Decodable, Sendable {
    let observed_at_ms: Int64
    let value: SkyValue
    let unit: String
    let quality: String
}

actor SkyWireClient {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let token: String
    private let clientName: String
    private var connection: NWConnection?
    private var buffer = Data()
    private var nextID: UInt64 = 1
    private var requestInFlight = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    init(host: String = "127.0.0.1", port: UInt16 = 3636, token: String, clientName: String = "skyHAB.macos") {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
        self.token = token
        self.clientName = clientName
    }

    func connect() async throws {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        self.connection = connection
        do {
            let gate = ContinuationGate()
            try await withCheckedThrowingContinuation { continuation in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard gate.claim() else { return }
                        connection.stateUpdateHandler = nil
                        continuation.resume()
                    case .failed(let error):
                        guard gate.claim() else { return }
                        connection.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    case .cancelled:
                        guard gate.claim() else { return }
                        connection.stateUpdateHandler = nil
                        continuation.resume(throwing: SkyWireError.disconnected)
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .userInitiated))
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10) {
                    guard gate.claim() else { return }
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    continuation.resume(throwing: SkyWireError.timeout("connecting to skyhabd"))
                }
            }
            _ = try await receiveMessage(timeout: 10)
            _ = try await request("AUTH", ["client": clientName, "token": token])
        } catch {
            invalidateConnection()
            throw error
        }
    }

    func disconnect() {
        invalidateConnection()
    }

    func resources() async throws -> [SkyResource] {
        try JSONDecoder().decode([SkyResource].self, from: try await requestJSON("RESOURCE.LIST"))
    }

    func views() async throws -> [SkyViewSummary] {
        try JSONDecoder().decode([SkyViewSummary].self, from: try await requestJSON("VIEW.LIST"))
    }

    func relationships() async throws -> [SkyRelationship] {
        try JSONDecoder().decode([SkyRelationship].self, from: try await requestJSON("RELATIONSHIP.LIST"))
    }

    func events(limit: Int = 40) async throws -> [SkyStateEvent] {
        try JSONDecoder().decode([SkyStateEvent].self, from: try await requestJSON("EVENT.LIST", ["limit": String(limit)]))
    }

    func storageFiles(resource: String, limit: Int = 50) async throws -> SkyStorageFileListing {
        try JSONDecoder().decode(SkyStorageFileListing.self, from: try await requestJSON("STORAGE.FILES", ["resource": resource, "limit": String(limit)]))
    }

    func view(id: String) async throws -> SkyPresentationView {
        try JSONDecoder().decode(SkyPresentationView.self, from: try await requestJSON("VIEW.DESCRIBE", ["id": id]))
    }

    func serviceDescription() async throws -> SkyServiceDescription {
        try JSONDecoder().decode(SkyServiceDescription.self, from: try await requestJSON("SERVICE.DESCRIBE"))
    }

    func state() async throws -> [StateRow] {
        try JSONDecoder().decode([StateRow].self, from: try await requestJSON("STATE.GET"))
    }

    func cameraStreamURL(resource: String) async throws -> String {
        guard let record = try await request("CAMERA.STREAM", ["resource": resource]) as? [String: Any],
              let text = record["url"] as? String, text.hasPrefix("rtsp://"),
              text.dropFirst("rtsp://".count).contains("@") else {
            throw SkyWireError.malformed("invalid camera stream URL")
        }
        return text
    }

    func assetPhoto(resource: String) async throws -> SkyAssetPhoto {
        guard let record = try await request("ASSET.PHOTO.GET", ["resource": resource]) as? [String: Any],
              let encoded = record["data"] as? String, let data = Data(base64Encoded: encoded) else {
            throw SkyWireError.malformed("invalid asset photo")
        }
        return SkyAssetPhoto(data: data, mime: record["mime"] as? String ?? "image/jpeg")
    }

    func setAssetPhoto(resource: String, revision: UInt64, mime: String, data: Data) async throws {
        _ = try await request("ASSET.PHOTO.SET", ["resource": resource, "revision": String(revision),
                                                   "mime": mime, "data": data.base64EncodedString()])
    }

    func deleteAssetPhoto(resource: String, revision: UInt64) async throws {
        _ = try await request("ASSET.PHOTO.DELETE", ["resource": resource, "revision": String(revision)])
    }

    func metric(resource: String, metric: String, since: Date, until: Date = Date()) async throws -> [MetricPoint] {
        try JSONDecoder().decode([MetricPoint].self, from: try await requestJSON("METRIC.QUERY", [
            "resource": resource, "metric": metric,
            "start_ms": String(Int64(since.timeIntervalSince1970 * 1000)),
            "end_ms": String(Int64(until.timeIntervalSince1970 * 1000)), "limit": "10000"
        ]))
    }

    func patch(id: String, revision: UInt64, changes: [String: Any]) async throws -> UInt64 {
        let bytes = try JSONSerialization.data(withJSONObject: changes)
        let text = String(decoding: bytes, as: UTF8.self)
        let result = try await request("INVENTORY.PATCH", ["id": id, "revision": String(revision), "changes": text])
        return (result as? [String: Any])?["revision"] as? UInt64 ?? revision
    }

    func patchComponent(resource: String, revision: UInt64, changes: [String: Any]) async throws {
        let bytes = try JSONSerialization.data(withJSONObject: changes)
        let text = String(decoding: bytes, as: UTF8.self)
        _ = try await request("COMPONENT.PATCH", ["resource": resource, "revision": String(revision), "changes": text])
    }

    func patchMetadata(resource: String, revision: UInt64, changes: [String: Any]) async throws {
        let bytes = try JSONSerialization.data(withJSONObject: changes)
        let text = String(decoding: bytes, as: UTF8.self)
        _ = try await request("METADATA.PATCH", ["resource": resource, "revision": String(revision), "changes": text])
    }

    func inventoryRevision() async throws -> UInt64 {
        let value = try await request("INVENTORY.GET") as? [String: Any]
        return (value?["revision"] as? NSNumber)?.uint64Value ?? 0
    }

    func setPinned(resource: String, pinned: Bool) async throws {
        let revision = try await inventoryRevision()
        _ = try await request("PIN.SET", ["resource": resource, "pinned": pinned ? "true" : "false", "revision": String(revision)])
    }

    func invoke(resource: String, action: String, parameters: [String: String] = [:]) async throws {
        let bytes = try JSONEncoder().encode(parameters)
        _ = try await request("ACTION.INVOKE", ["resource": resource, "action": action,
                                                "parameters": String(decoding: bytes, as: UTF8.self)])
    }

    private func request(_ command: String, _ arguments: [String: String] = [:]) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await requestJSON(command, arguments))
    }

    // Returns the raw response record bytes so typed callers can decode once,
    // directly. The former path serialized to Any via JSONSerialization and then
    // re-encoded to Data for JSONDecoder — three passes over the ~1.1 MiB
    // STATE.GET payload on every 5 s client poll.
    private func requestJSON(_ command: String, _ arguments: [String: String] = [:]) async throws -> Data {
        await acquireRequestSlot()
        defer { releaseRequestSlot() }
        do {
            let id = nextID; nextID += 1
            var tokens = ["Q", String(id), command]
            for key in arguments.keys.sorted() { tokens.append(key); tokens.append("s" + arguments[key]!) }
            try await send(Self.message(tokens), timeout: 10)
            let timeout: TimeInterval = command == "ACTION.INVOKE" ? 45 : command == "METRIC.QUERY" || command.hasPrefix("ASSET.PHOTO.") ? 20 : 12
            while true {
                let response = try await receiveMessage(timeout: timeout)
                guard response.count >= 3, response[0] == "R", response[1] == String(id) else { continue }
                if response[2] == "ERR" { throw SkyWireError.server(response.count > 5 ? response[5] : "server error") }
                guard response.count >= 6, response[4] == "json" else { throw SkyWireError.malformed("missing JSON record") }
                return Data(response[5].dropFirst().utf8)
            }
        } catch {
            invalidateConnection()
            throw error
        }
    }

    private func acquireRequestSlot() async {
        if !requestInFlight { requestInFlight = true; return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    private func releaseRequestSlot() {
        if requestWaiters.isEmpty { requestInFlight = false }
        else { requestWaiters.removeFirst().resume() }
    }

    private func send(_ data: Data, timeout: TimeInterval) async throws {
        guard let connection else { throw SkyWireError.disconnected }
        let gate = ContinuationGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                guard gate.claim() else { return }
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                guard gate.claim() else { return }
                connection.cancel()
                continuation.resume(throwing: SkyWireError.timeout("sending a SkyWire request"))
            }
        }
    }

    private func receiveMessage(timeout: TimeInterval) async throws -> [String] {
        while true {
            if let tokens = try Self.decode(&buffer) { return tokens }
            guard let connection else { throw SkyWireError.disconnected }
            let gate = ContinuationGate()
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                    guard gate.claim() else { return }
                    if let error { continuation.resume(throwing: error) }
                    else if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: SkyWireError.disconnected) }
                    if complete { connection.cancel() }
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                    guard gate.claim() else { return }
                    connection.cancel()
                    continuation.resume(throwing: SkyWireError.timeout("waiting for a SkyWire response"))
                }
            }
            buffer.append(data)
        }
    }

    private func invalidateConnection() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
    }

    static func netstring(_ data: Data) -> Data {
        var result = Data("\(data.count):".utf8); result.append(data); result.append(0x2c); return result
    }
    static func message(_ tokens: [String]) -> Data {
        var payload = Data(); for token in tokens { payload.append(netstring(Data(token.utf8))) }; return netstring(payload)
    }
    static func decode(_ input: inout Data) throws -> [String]? {
        func one(_ data: Data, _ offset: Int) throws -> (Data, Int)? {
            guard offset <= data.count else { throw SkyWireError.malformed("offset") }
            let from = data.index(data.startIndex, offsetBy: offset)
            guard let colon = data[from...].firstIndex(of: 0x3a) else { return nil }
            guard let length = Int(String(decoding: data[from..<colon], as: UTF8.self)), length <= 16 * 1_048_576 else { throw SkyWireError.malformed("length") }
            let start = data.index(after: colon)
            guard data.distance(from: start, to: data.endIndex) > length else { return nil }
            let end = data.index(start, offsetBy: length)
            guard data[end] == 0x2c else { throw SkyWireError.malformed("comma") }
            let consumed = data.distance(from: data.startIndex, to: data.index(after: end))
            return (Data(data[start..<end]), consumed)
        }
        guard let (payload, consumed) = try one(input, 0) else { return nil }
        var tokens: [String] = [], offset = 0
        while offset < payload.count { guard let (token, next) = try one(payload, offset) else { throw SkyWireError.malformed("inner") }; tokens.append(String(decoding: token, as: UTF8.self)); offset = next }
        input.removeFirst(consumed); return tokens
    }
}
