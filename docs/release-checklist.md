# Release checklist

## Automated local checks

- [x] Unit, integration, malformed-input, allocation-limit, export, and performance tests compile and pass on the current M1 host.
- [x] Release-Direct and Release-AppStore build as universal x86_64 + arm64 applications.
- [x] x86_64 declares macOS 10.15; arm64 declares macOS 11.0.
- [x] No SwiftUI or WebKit linkage is present.
- [x] Direct has no App Sandbox entitlement.
- [x] App Store has only App Sandbox, user-selected read-only files, and app-scoped bookmarks; it has no network entitlement.
- [x] Both local ad hoc artifacts carry Hardened Runtime and pass strict code-signature verification.
- [x] Both configurations pass current-system startup smoke.
- [x] English and Simplified Chinese localization keys match.
- [x] Third-party source licenses are present.
- [ ] UI automation executes. Tests compile, but the current host reports `Timed out while enabling automation mode` before any test runs.
- [ ] Address Sanitizer executes. The Xcode 26 hostless XCTest runner builds the ASan bundle but aborts before tests because its interceptors load too late.

## Distribution signing

The generated artifacts are intentionally ad hoc signed for local verification. Gatekeeper rejects both and stapler reports no ticket, which is expected and was verified on 2026-08-28.

- [ ] Sign Direct with a Developer ID Application certificate.
- [ ] Submit Direct for notarization, staple the accepted ticket, and require `spctl --assess` plus `stapler validate` to pass.
- [ ] Sign/archive App Store with the correct Mac App Distribution profile and validate/upload through Xcode or Transporter.
- [ ] Confirm App Store receipt/sandbox behavior in a TestFlight or store-signed build.

Set `LIGHTVIEW_REQUIRE_DISTRIBUTION_SIGNATURE=1` when running `scripts/verify-compatibility.sh` against a distribution-signed artifact; this changes missing Developer ID/Gatekeeper/notarization evidence from an expected local state to a failure.

## Manual compatibility gates

- [ ] Intel macOS 10.15 test row completed in `compatibility-matrix.md`.
- [ ] Current Intel macOS test row completed.
- [ ] Apple silicon macOS 11 test row completed.
- [x] Current Apple silicon smoke completed on Apple M1/macOS 26.6.2.
- [ ] English and Simplified Chinese visual pass, keyboard-only traversal, VoiceOver labels, full-screen entry/exit, multiwindow behavior, sandbox folder authorization/cancel/restore, and completed MP4 export.

## Reproducible commands

```bash
./scripts/build-universal.sh Release-Direct
./scripts/build-universal.sh Release-AppStore
./scripts/verify-compatibility.sh build/releases/Release-Direct/LightView.app Release-Direct
./scripts/verify-compatibility.sh build/releases/Release-AppStore/LightView.app Release-AppStore
./scripts/smoke-release.sh
```
