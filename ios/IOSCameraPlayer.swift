// skyHAB Project <src@lispm.net>
// Copyright (c) 2026 I. Finder
// SPDX-License-Identifier: MIT

import SwiftUI

#if canImport(MobileVLCKit)
import MobileVLCKit

struct IOSEmbeddedCameraPlayer: UIViewRepresentable {
    let stream: String

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        // libVLC needs a drawable that has joined a window. Starting inline from
        // makeUIView races SwiftUI's sheet attachment and can produce a black frame.
        DispatchQueue.main.async { context.coordinator.start(stream: stream, drawable: view) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.start(stream: stream, drawable: view)
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject {
        // Use VLCKit's shared library. Supplying constructor options creates a
        // private libVLC instance per sheet and makes RTSP startup materially slower.
        private let player = VLCMediaPlayer()
        private var playingStream = ""
        func start(stream: String, drawable: UIView) {
            player.drawable = drawable
            guard stream != playingStream else {
                if !player.isPlaying { player.play() }
                return
            }
            guard let url = URL(string: stream) else { return }
            playingStream = stream
            let media = VLCMedia(url: url)
            media.addOptions([
                "rtsp-tcp": true,
                "network-caching": 80,
                "live-caching": 80,
                "clock-jitter": 0,
                "clock-synchro": 0,
                "drop-late-frames": true,
                "skip-frames": true,
                "no-audio": true
            ])
            player.media = media
            player.audio?.volume = 0
            player.play()
        }
        func detach() {
            player.drawable = nil
            // VLC teardown can wait on its RTSP worker. Never make sheet dismissal
            // wait on that synchronization.
            performSelector(inBackground: #selector(stopPlayer), with: nil)
        }
        @objc private func stopPlayer() {
            player.stop()
            player.media = nil
            playingStream = ""
        }
    }
}
#else
struct IOSEmbeddedCameraPlayer: View {
    let stream: String
    var body: some View { Text("Embedded video dependency is unavailable").foregroundStyle(.secondary) }
}
#endif
