// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import SwiftUI

private struct AcquisitionBarberPole: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SkyTheme.inset))
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8 * 24
                var x = -36.0 + phase
                while x < size.width + 24 {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: x, y: size.height))
                    stripe.addLine(to: CGPoint(x: x + 10, y: size.height))
                    stripe.addLine(to: CGPoint(x: x + 24, y: 0))
                    stripe.addLine(to: CGPoint(x: x + 14, y: 0))
                    stripe.closeSubpath()
                    context.fill(stripe, with: .color(SkyTheme.amber))
                    x += 24
                }
            }
        }
        .frame(width: 190, height: 13).vintageInset()
    }
}

final class RTSPFramePlayer: ObservableObject, @unchecked Sendable {
    @Published var image: NSImage?
    @Published var error = ""
    private var process: Process?
    private let decodeQueue = DispatchQueue(label: "skyhab.camera.decode")
    private var buffer = Data()
    private var stderrTail = ""

    func start(url: URL) {
        stop()
        guard let executable = ["/opt/local/bin/ffmpeg", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            error = "ffmpeg is not installed"
            return
        }
        let process = Process()
        let video = Pipe()
        let diagnostics = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-hide_banner", "-loglevel", "warning", "-rtsp_transport", "tcp",
            "-fflags", "nobuffer", "-flags", "low_delay", "-analyzeduration", "100000", "-probesize", "100000",
            "-i", url.absoluteString, "-an", "-vf", "scale=1280:-2:flags=fast_bilinear", "-fps_mode", "passthrough",
            "-f", "image2pipe", "-vcodec", "mjpeg", "-q:v", "4", "pipe:1"
        ]
        process.standardOutput = video
        process.standardError = diagnostics
        video.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let player = self else { return }
            player.decodeQueue.async { player.consume(data) }
        }
        diagnostics.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), let player = self else { return }
            player.decodeQueue.async { player.stderrTail = String(player.stderrTail + text).suffix(1200).description }
        }
        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                guard self?.process === process else { return }
                self?.error = self?.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? self!.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "Camera decoder stopped"
            }
        }
        do {
            try process.run()
            self.process = process
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        let oldProcess = process
        oldProcess?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        oldProcess?.standardError.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        process = nil
        if oldProcess?.isRunning == true {
            DispatchQueue.global(qos: .utility).async {
                oldProcess?.terminate()
                oldProcess?.waitUntilExit()
            }
        }
        decodeQueue.async { [weak self] in self?.buffer.removeAll(keepingCapacity: false) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        let startMarker = Data([0xff, 0xd8]), endMarker = Data([0xff, 0xd9])
        while let start = buffer.range(of: startMarker)?.lowerBound {
            if start > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<start) }
            guard let end = buffer.range(of: endMarker, in: buffer.index(buffer.startIndex, offsetBy: 2)..<buffer.endIndex)?.upperBound else { break }
            let frame = Data(buffer[buffer.startIndex..<end])
            buffer.removeSubrange(buffer.startIndex..<end)
            DispatchQueue.main.async { [weak self] in
                guard let image = NSImage(data: frame) else { return }
                self?.image = image
                self?.error = ""
            }
        }
        if buffer.count > 12_000_000 { buffer.removeAll(keepingCapacity: true) }
    }

    deinit { stop() }
}

struct CameraViewer: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = RTSPFramePlayer()
    let resource: SkyResource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resource.pretty_name).font(.custom("Helvetica Neue", size: 15).weight(.bold)).tracking(0.3)
                    HStack(spacing: 6) {
                        Circle().fill(player.image == nil ? SkyTheme.amber : SkyTheme.phosphor).frame(width: 7, height: 7)
                        Text(player.image == nil ? "Sync" : "Live").font(.caption2.monospaced().bold())
                        Text(resource.address).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("Close") { dismiss() }.buttonStyle(VintageButtonStyle())
            }
            .padding(9).vintagePanel(SkyTheme.face)
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Color.black)
                    if let image = player.image {
                        Image(nsImage: image).resizable().interpolation(.medium).scaledToFit()
                    } else if player.error.isEmpty {
                        VStack(spacing: 10) { AcquisitionBarberPole(); Text("Acquiring video").font(.caption.monospaced()) }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit).frame(minWidth: 720, minHeight: 405)
                .padding(7).vintageInset(.black)
            }.padding(9).vintagePanel(SkyTheme.panel)
            if !player.error.isEmpty {
                Text(player.error).font(.caption.monospaced()).foregroundStyle(.red).lineLimit(3).textSelection(.enabled)
            }
            HStack {
                Text("skyHAB video terminal").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(); Text("RTSP / native rate").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 5)
        }
        .padding(12).vintagePanel(SkyTheme.face).padding(8).background { Rectangle().fill(SkyTheme.background) }
        .task {
            do { player.start(url: try await model.cameraURL(resource)) }
            catch { player.error = String(describing: error) }
        }
        .onDisappear { player.stop() }
    }
}
