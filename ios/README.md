# skyHAB for iPhone and iPad

The native iOS client is part of skyHAB—the sky Habitat Automation Builder. Build the workspace,
not the bare Xcode project:

```sh
bundle install
bundle exec pod install --project-directory=ios
xcodebuild -workspace ios/skyHAB.xcworkspace -scheme skyHAB -sdk iphonesimulator \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

The workspace compiles the exact shared `SkyWireClient.swift`, `DashboardModel.swift`, and
`PresentationProjections.swift` sources from the macOS package. iOS owns only its application
lifecycle, navigation shell, touch controls, and platform-specific camera player.

The checked-in client configuration points to loopback and contains no token. Enter a deployment
host, unique client identity, and token in Settings. Private release builds may supply their own
configuration during packaging; do not commit it.

## Camera playback

MobileVLCKit 3.3.16.3 is deliberately pinned for low-latency RTSP/TCP playback. A tested newer
series caused slow startup and multi-second frame stalls over VPN. Any upgrade requires a
physical-device camera test over the actual remote path, including app backgrounding and prompt
dismissal. Camera URLs may contain credentials and must never appear in logs or screenshots.

## Layout

The compact shell uses push navigation. Wide iPhone/foldable and iPad canvases use a persistent
module rail beside the selected console. Both consume the same server-described views and state.
