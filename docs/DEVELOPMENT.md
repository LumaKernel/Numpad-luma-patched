# Developing Numpad

[← Back to Numpad](../README.md)

## Requirements and builds

Use macOS 13+, Swift 5.9+ and Xcode Command Line Tools.

```sh
swift test
bash scripts/build-app.sh
open dist/Numpad.app
```

The default build targets the current Mac architecture and uses an ad hoc signature for local testing. `UNIVERSAL=1 bash scripts/build-app.sh` includes arm64 and x86_64. `VERSION` is the source of the release version. The executable target remains `TrackpadNumpad`. The app bundle identifier and code-signing identifier are `com.yftech.TrackpadNumpad`. Published releases through 0.0.2 used `dev.yeonfish.TrackpadNumpad`; macOS treats the new identifier as a separate app for preferences and Accessibility permissions.

## Codebase

| Path | Responsibility |
| --- | --- |
| `Sources/CTrackpad` | Load MultitouchSupport, receive normalized touch coordinates, drive haptics |
| `Sources/TrackpadCore` | Key mapping, tap recognition, anchors, calibration, overlay placement and snapping, localization |
| `Sources/TrackpadNumpad` | Input monitoring, right-hand shortcut, menu bar, SwiftUI settings and overlay |
| `Tests/TrackpadCoreTests` | Input behavior, calibration, placement, snapping, language defaults and translation catalogs |
| `scripts/build-app.sh` | App bundle, localization resources, icon generation, signing |
| `scripts/build-dmg.sh` | Universal DMG, Applications shortcut, optional notarization, SHA-256 checksums |

## Localization

English is the explicit initial language, even when macOS prefers Korean. The in-app **General → Language** picker persists `appLanguage` as `en` or `ko` and updates settings, menus, window titles, overlay hints, and stored status messages without a restart.

Editable catalogs live in `Sources/TrackpadCore/Resources/{en,ko}.lproj/Localizable.strings`. English source strings are the keys. Keep key sets and `%d` placeholders aligned. `LocalizedMessage` retains the source key and optional finger count so a previous calibration message can be displayed in either language. C bridge errors use English keys and are translated at the app boundary.

SwiftPM builds the resource bundle; the app build script copies it into `Contents/Resources`. Verify translations in the packaged executable:

```sh
dist/Numpad.app/Contents/MacOS/TrackpadNumpad --check-localization
```

## Diagnostics

```sh
# Framework availability, default trackpad, Accessibility, stream start and stop
dist/Numpad.app/Contents/MacOS/TrackpadNumpad --diagnose

# Start with Settings visible
dist/Numpad.app/Contents/MacOS/TrackpadNumpad --settings

# Show the overlay and quit after two seconds
dist/Numpad.app/Contents/MacOS/TrackpadNumpad --smoke-test

# One haptic pulse and driver result
dist/Numpad.app/Contents/MacOS/TrackpadNumpad --test-haptic
```

`--diagnose` does not open a GUI or request permission. A successful stream start does not verify actual taps or delivery to another app.

## Input behavior

- A valid tap lasts 25–450 ms and types once on release. Swipes, long holds, and extra typing contacts cancel it.
- A stationary contact becomes an anchor after about 120 ms. When two contacts land together, a contact near the center of `5` can anchor immediately. Movement of the anchor by normalized distance 0.08 or its release cancels the current tap until all fingers lift.
- The center detent for `5` uses an ellipse in key-relative coordinates: entry radius 3.5%, exit radius 5.5%. This hysteresis avoids repeated haptics from boundary noise. Landing directly at the center and lifting off are not crossing events.
- Pressure-zero clicks during or within 250 ms of trackpad contact are classified as tap-to-click and blocked. Physical click down/drag/up are paired and allowed while cancelling the current numeric tap.
- A new confirmed input cancels the previous highlight clear task. Highlighting turns on immediately, stays for 160 ms after the latest input, then fades over 80 ms. Reduce Motion disables the fade.
- Three-finger calibration uses `4·5·6`, anchoring `5` to the middle finger. Four-finger calibration uses the middle contacts at `×·−`. Both preserve key proportions through translation, rotation, and uniform scale.

## Signed DMG releases

Install a **Developer ID Application** certificate and private key. Store notarization credentials locally in Keychain:

```sh
xcrun notarytool store-credentials Numpad
```

Then build:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=Numpad \
bash scripts/build-dmg.sh
```

The script enables hardened runtime, timestamps the app signature, notarizes the app, staples its ticket, creates and signs the DMG, notarizes and staples the DMG, and checks Gatekeeper acceptance. Output: `dist/Numpad-<version>-universal.dmg` and its SHA-256 checksum file.

Without signing credentials, `bash scripts/build-dmg.sh` produces a local test DMG with no notarization. Do not publish it as a notarized release. Keep credentials and private keys out of the repository.

## Platform notes

MultitouchSupport and some actuator/UniversalAccess calls are private Apple APIs. This project does not target App Store distribution. Trackpad hot-plugging is unsupported. Zoom preferences are restored on mode exit and application termination; after an abnormal exit, recovery happens at the next launch.

Signing identity or installation location changes can affect Accessibility permissions. If access fails after a local rebuild, remove and re-add the app in System Settings.

## API references

- [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport)
- [Multitouch ABI](https://github.com/ZaynJarvis/trackpad-studio/blob/master/Sources/CMultitouchShim/include/CMultitouchShim.h)
- [Actuator example](https://gist.github.com/niw/b120b460e854ec10cefeeb60784f5dbb)
- [Apple CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [Apple haptics](https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer)
