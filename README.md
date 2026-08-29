# LightView

<img src="Resources/AppIcon/LightView-master.png" alt="LightView application icon" width="128">

LightView is a lightweight, native image viewer for macOS, written in Swift with AppKit. It combines the focused viewing, folder navigation, animation, slideshow, image information, and MP4-export capabilities selected from qView and Tovi in a new codebase. It does not use SwiftUI, WebKit, Qt, Electron, or browser rendering.

The current code is a release candidate, not a notarized public release. It builds and runs on the current Apple silicon test Mac; Intel Catalina and Apple silicon Big Sur remain explicit real-system release gates.

## Highlights

- Native multiwindow viewer with drag and drop, Open Recent, Finder open events, and non-recursive folder navigation.
- Fit, fill, actual size, pointer-anchored zoom, pan, rotate, flip, and full screen. The live window title shows folder position, filename, zoom, displayed/original dimensions, file size, format, and animation frame count when applicable.
- Structured EXIF display for ImageIO formats, including HEIC: press **E** for a translucent canvas overlay, or **Command-I** for the complete File & Image / EXIF information window. Images without meaningful EXIF never show an empty overlay.
- Static ImageIO formats, safe NanoSVG-based SVG rendering, static/animated WebP fallback through decoder-only libwebp, plus GIF and APNG playback.
- Forward/reverse slideshow and silent H.264 MP4 export at 480p, 720p, or 1080p with fit/fill, backgrounds, slide/fade transitions, progress, and cancellation.
- Typed AppKit preferences for appearance, background, folder order, wrapping, preload, zoom, slideshow interval, energy saving, window resize, and welcome-guide visibility.
- Two configurations from the same source: unsandboxed Direct and sandboxed App Store.
- Original LightView app icon supplied through a Catalina-compatible macOS Asset Catalog, with 16–1024 px representations.
- No telemetry, accounts, ads, image upload, network image loading, or in-app updater.

The native welcome window is the feature/shortcut overview. It can be reopened from **Help → LightView Guide** and disabled for new empty windows in Settings.

## Compatibility and formats

Release artifacts are Universal 2 but deliberately use different slice minimums:

| CPU | Declared minimum | Verification state |
|---|---|---|
| Intel x86_64 | macOS 10.15 Catalina | Binary verified; real Catalina launch pending |
| Apple silicon arm64 | macOS 11 Big Sur | Binary verified; real Big Sur launch pending |
| Apple M1 | macOS 26.6.2 | Direct and App Store local startup smoke passed |

ImageIO handles formats supported by the running macOS, including JPEG, PNG, GIF, TIFF, BMP, ICO, JPEG 2000, HEIF/HEIC, and supported RAW types. SVG uses the bundled lightweight parser and never executes scripts or external resources. WebP first tries ImageIO, then falls back to bundled decoder-only libwebp; static and animated WebP therefore work across the supported OS range. AVIF is native-only and requires a macOS version whose ImageIO accepts the file (the application policy requires macOS 13 or later); no AV1 decoder is bundled.

See [compatibility-matrix.md](docs/compatibility-matrix.md) for the distinction between binary evidence and real-system evidence.

## Fixed shortcuts

| Action | Shortcut |
|---|---|
| Open / new / close | Command-O / Command-N / Command-W |
| Previous / next | Left / Right Arrow |
| First / last | Command-Left / Command-Right |
| Zoom in / out | Plus / Minus |
| Fit / fill / actual size | F / Shift-F / 1 |
| Show or hide EXIF overlay | E |
| Rotate left / right | Shift-Left / Shift-Right |
| Flip horizontal / vertical | H / V |
| Full screen | Control-Command-F |
| Play or pause animation | Space |
| Start or stop slideshow | Return |
| File information | Command-I |
| Reload | Command-R |
| Export MP4 | Command-E |

Escape closes a viewer outside full screen. Mouse dragging or scrolling pans; trackpad pinch zooms around the interaction point. Shortcuts are intentionally not customizable. LightView does not implement copy, paste, rename, Trash/delete, or file-operation undo.

## Direct and App Store behavior

`Release-Direct` uses ordinary read access and has no App Sandbox entitlement. `Release-AppStore` is sandboxed with user-selected read-only access and app-scoped bookmarks. The selected image opens immediately; adjacent navigation asks for its folder only when broader permission is needed. MP4 output is created through the user-selected `NSSavePanel` destination. The two channels have the same viewer/export feature code and are alternatives, not side-by-side editions.

Local artifacts default to ad hoc signing with Hardened Runtime for verification. The GitHub v1.0.0 Direct arm64 and x86_64 DMGs, together with the applications they contain, are signed with Developer ID, notarized by Apple, and carry stapled tickets. App Store distribution still requires the correct distribution profile and store validation.

## Build and test

Requirements: macOS, Xcode with the macOS 10.15 SDK compatibility needed by the current project, Git submodules, and standard command-line build tools.

```bash
git submodule update --init --recursive
./scripts/build-universal.sh Release-Direct
./scripts/build-universal.sh Release-AppStore
./scripts/verify-compatibility.sh build/releases/Release-Direct/LightView.app Release-Direct
./scripts/verify-compatibility.sh build/releases/Release-AppStore/LightView.app Release-AppStore
xcodebuild -project LightView.xcodeproj -scheme LightView -configuration Debug test \
  -only-testing:LightViewTests CODE_SIGNING_ALLOWED=NO
```

For a Developer ID build, set `LIGHTVIEW_CODE_SIGN_IDENTITY` to the full certificate name. The build script then requests a secure timestamp automatically; ad hoc builds continue to use no timestamp.

The build script compiles the x86_64/10.15 and arm64/11.0 slices separately, verifies identical resource payloads, merges compatible Mach-O files, signs nested code and the application, and validates the result. See [release-checklist.md](docs/release-checklist.md) for outstanding UI-automation, sanitizer, App Store signing, and old-system gates.

## GitHub release

The release script builds separate Intel and Apple silicon DMGs, signs and notarizes both applications and disk images, creates the version tag, and publishes the assets through GitHub CLI. GitHub generates the source ZIP and TAR.GZ automatically from that tag.

```bash
./scripts/release-github.sh 1.0.1
```

It reads the version from `Resources/Info.plist` and refuses a mismatched argument, dirty working tree, or existing tag. No credentials are stored in the repository. By default it uses the `LightView-Notary` notarytool Keychain profile and the first valid Developer ID Application identity. These can be overridden locally:

```bash
LIGHTVIEW_NOTARY_PROFILE=LightView-Notary \
LIGHTVIEW_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
LIGHTVIEW_GITHUB_REPOSITORY=longbai/lightview \
./scripts/release-github.sh 1.0.1
```

## Measured resource use

On an Apple M1 MacBook Pro with 16 GB RAM and macOS 26.6.2, all four applications opened the same 2,153,248-byte 12000×8000 JPEG in three alternating cold-start rounds. Each round settled for five seconds and recorded five main-process RSS samples. Descendant-process RSS was zero in this accepted corpus.

| Application | `.app` logical | Main Mach-O | Median RSS | Relative RSS |
|---|---:|---:|---:|---:|
| LightView 0.1.0 | 4.23 MiB | 3.15 MiB universal | 149.20 MiB | 1.00× |
| Tovi 2.0.4 | 5.11 MiB | 0.87 MiB x86_64 | 408.62 MiB | 2.74× |
| qView 7.1 | 116.41 MiB | 3.19 MiB universal | 519.72 MiB | 3.48× |
| SimpView | 1.91 MiB | 1.10 MiB arm64 | 795.83 MiB | 5.33× |

Tovi was highly state-sensitive (roughly 33–409 MiB across the three runs). Existing global WebKit process RSS did not change during those runs, so no helper increment was added; that does not establish zero WebKit cost. RSS includes shared pages and is not private footprint. Full methodology, ranges, hashes, identities, raw TSVs, and the superseded launch method are in [benchmark-results.md](benchmark-results.md) and [the accepted benchmark summary](benchmarks/results/2026-08-28/summary.md). Re-run with `./scripts/benchmark-suite.sh`; individual runs use `./scripts/benchmark-app.sh APP FIXTURE LABEL OUTPUT_TSV`.

After the EXIF, HEIC, title, and application-icon changes, the final Direct binary was rechecked alone for three rounds (15 samples): median 137.45 MiB, mean 130.99 MiB, range 105.59–159.58 MiB, with no descendants. Its current logical bundle size is 7.01 MiB and its universal main Mach-O is 3.31 MiB; most bundle growth comes from the 2.50 MiB compiled icon asset catalog. This is a final-binary regression check, not a replacement for the alternating four-application comparison. The raw samples are in `raw/final-lightview-exif-icon.tsv` beside the accepted corpus.

## Architecture and scope

`AppCoordinator` owns application-wide menus and services. Each `ViewerWindowController` owns an independent `ViewingSession`; the session coordinates a cancellable `ImageLoadPipeline`, `FolderCatalog`, playback controllers, and the layer-backed `ImageCanvasView`. Decoder, cache, viewport geometry, access, playback, and export boundaries are independently tested. This naming and structure were designed for LightView and do not follow SimpView's architecture.

Product behavior is specified in [requirements.md](docs/requirements.md), and implementation boundaries and tests are in [technical-spec.md](docs/technical-spec.md).

## Privacy and licenses

LightView processes local files on the device. It has no network entitlement in the App Store configuration and no product code for telemetry, analytics, advertising, accounts, uploads, or remote images. SVG scripts, foreign objects, and external resources are rejected.

LightView includes modified NanoSVG source and decoder-only libwebp components. Their notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the pinned upstream source trees under `Vendor/`. qView, Tovi, and SimpView are comparison subjects only; no source or assets from them are included.
