# Third-party notices

skyHAB includes or depends on third-party software. This summary is informational; the original
license text distributed with each component controls.

- [JSON for Modern C++ 3.11.3](https://github.com/nlohmann/json), © Niels Lohmann and
  contributors — MIT License. The vendored single header in `third_party/nlohmann/` has SHA-256
  `9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6` and matches the official
  3.11.3 release file.
- [PicoSHA2](https://github.com/okdshin/PicoSHA2), © okdshin — MIT License. The vendored header
  in `third_party/picosha2.h` has SHA-256
  `b13c180161ffac8d0adc81e033e493c409457c4d1258ab9781ac80579ba3bdd8` and matches the upstream
  file audited for this release.
- [MobileVLCKit 3.3.16.3](https://code.videolan.org/videolan/VLCKit) and VLC — the pinned CocoaPods
  binary includes the GNU Lesser General Public License version 2.1 notice. CocoaPods resolves the
  dependency; it is not committed to this repository. Distributors of application binaries must
  review and satisfy the notices, source-availability, relinking, and other applicable obligations
  shipped with that binary.
- SQLite is linked from the operating system/toolchain and is in the public domain.

Review dependency licenses when distributing binaries, especially MobileVLCKit/VLC obligations.

Apple and other product and company names are trademarks of their respective owners and are used
only to describe compatibility. skyHAB is independent and is not affiliated with or endorsed by
those owners.
