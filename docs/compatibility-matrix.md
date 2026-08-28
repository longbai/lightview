# Compatibility matrix

LightView intentionally builds two slices with different minimum systems: x86_64 targets macOS 10.15 and arm64 targets macOS 11.0. Static inspection proves what the binary declares; only launch testing on the named operating system proves runtime compatibility.

| Platform | Binary evidence | Real launch evidence | Status |
|---|---|---|---|
| Intel, macOS 10.15 Catalina | x86_64 slice; `LC_BUILD_VERSION minos 10.15`; no SwiftUI/WebKit linkage | Not available in the current lab | Pending real-system test |
| Intel, current supported macOS | x86_64 slice present | Not available in the current lab | Pending real-system test |
| Apple silicon, macOS 11 Big Sur | arm64 slice; `LC_BUILD_VERSION minos 11.0`; no SwiftUI/WebKit linkage | Not available in the current lab | Pending real-system test |
| Apple M1, macOS 26.6.2 (25G83) | arm64 slice selected natively | Direct and App Store configurations launched and remained alive in three-second smoke tests | Pass for current system |

## Current automated evidence

- `scripts/build-universal.sh` independently builds x86_64/10.15 and arm64/11.0, compares resource payloads, merges only compatible Mach-O slices, signs nested code, and invokes artifact verification.
- `scripts/verify-artifact.sh` checks both architectures, per-slice minimum OS, code integrity, forbidden SwiftUI/WebKit linkage, localized resources, and configuration-specific entitlements.
- `scripts/verify-compatibility.sh` additionally checks Hardened Runtime, distribution-channel metadata, and vendored license presence.
- Direct and App Store artifacts passed startup smoke on the current Apple M1 host. The Direct build also opened and displayed the 12000×8000 JPEG during the three-round performance comparison.
- Sandbox bookmark/provider unit and integration tests pass. UI automation compiled, but Xcode could not enable automation mode on this host, so interactive folder-panel behavior remains a manual release check.

## Required old-system test procedure

For both an Intel Catalina machine and an Apple silicon Big Sur machine:

1. Copy the exact hashed Direct artifact without rebuilding it.
2. Confirm native architecture with Activity Monitor or `ps -o arch`.
3. Open JPEG/PNG, SVG, static WebP, animated GIF/WebP, and a folder; navigate both directions.
4. Export a short 480p H.264 MP4 and inspect duration/dimensions with AVFoundation or `ffprobe`.
5. Record model (without serial number), OS build, artifact SHA-256, tester, date, and pass/fail here.

Until those rows are completed, Catalina and Big Sur support is an engineered target, not a field-verified claim.
