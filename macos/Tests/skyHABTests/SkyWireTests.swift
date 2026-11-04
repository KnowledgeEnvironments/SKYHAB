// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import Foundation
import Testing
@testable import skyHAB

@Test func decoderHandlesRebasedDataAfterRemoval() throws {
    let message = SkyWireClient.message(["H", "1", "0", "skyhabd"])
    var buffer = Data([0xaa, 0xbb, 0xcc])
    buffer.removeFirst(3)
    buffer.append(message)
    let decoded = try SkyWireClient.decode(&buffer)
    #expect(decoded == ["H", "1", "0", "skyhabd"])
    #expect(buffer.isEmpty)
}

@Test func decoderHandlesFragmentedInput() throws {
    let message = SkyWireClient.message(["R", "9", "OK", "pong", "json", "s{}"])
    var buffer = Data()
    for byte in message.dropLast() { buffer.append(byte); #expect(try SkyWireClient.decode(&buffer) == nil) }
    buffer.append(message.last!)
    #expect(try SkyWireClient.decode(&buffer) == ["R", "9", "OK", "pong", "json", "s{}"])
}
