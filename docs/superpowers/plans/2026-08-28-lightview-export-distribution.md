# LightView Export and Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bounded H.264 MP4 slideshow export and deliver equivalent Direct and App Store release configurations with correct folder authorization.

**Architecture:** Export planning is pure and testable; frame composition writes into a reusable pixel-buffer pool; AVAssetWriter is isolated behind a protocol. Distribution differences are confined to entitlements and `FolderAccessProvider` selection.

**Tech Stack:** Swift, AppKit, AVFoundation, Core Video, Core Graphics, Foundation security-scoped bookmarks, XCTest, codesign tooling.

**Spec:** `docs/requirements.md` and `docs/technical-spec.md`

## Global Constraints

- Output is silent H.264 in an MP4 container at 480p, 720p, or 1080p.
- Export never retains the whole movie as raster frames.
- Cancellation removes only operation-owned temporary output.
- Direct and App Store builds share feature code and are not designed for side-by-side installation.
- App Store source access is read-only even though save-panel entitlement permits output creation.

---

### Task 1: Pure export plan and timeline

**Files:**
- Create: `Sources/Exporting/MovieExportTypes.swift`
- Create: `Sources/Exporting/ExportTimelineBuilder.swift`
- Create: `Tests/Unit/ExportTimelineBuilderTests.swift`

**Interfaces:**
- Produces: `MovieExportPlan`, `ExportSource`, `TransitionKind`, `AnimationDurationPolicy`, `FrameInstruction`, and `ExportTimelineBuilder.build(_:)`.

- [ ] **Step 1: Write exact timeline tests**

At 30 fps, assert a 2-second static image creates 60 frames; two 1-second images with a 0.25-second fade produce deterministic overlap instructions; finite animation loop, one-loop, and maximum-duration policies terminate at exact presentation timestamps.

- [ ] **Step 2: Run timeline tests**

Expected: FAIL because export types are undefined.

- [ ] **Step 3: Implement rational-time timeline construction**

Use `CMTime` with a 600 timescale and reject negative/zero dimensions, frame rates, and durations. Emit lightweight instructions referencing source indices and normalized transition progress; never attach decoded images to the timeline array.

- [ ] **Step 4: Run tests and commit**

```bash
git add Sources/Exporting Tests/Unit/ExportTimelineBuilderTests.swift
git commit -m "feat: define deterministic movie timeline"
```

### Task 2: Frame compositor

**Files:**
- Create: `Sources/Exporting/ExportFrameComposer.swift`
- Create: `Sources/Exporting/PixelBufferPool.swift`
- Create: `Tests/Unit/ExportFrameComposerTests.swift`

**Interfaces:**
- Produces: `ExportFrameComposer.compose(_:into:)` for fit/fill, background color/image, slide, and fade.
- Consumes: timeline instructions and source frame providers.

- [ ] **Step 1: Write pixel tests on a tiny deterministic canvas**

Use solid red and blue 4x2 fixtures. Assert letterbox background pixels, crop geometry, 50% fade channel values within one unit, and 50% slide positions. Assert the pool reuses buffers and remains below its configured count.

- [ ] **Step 2: Run compositor tests**

Expected: FAIL because compositor and pool are undefined.

- [ ] **Step 3: Implement BGRA composition into CVPixelBuffer memory**

Lock the base address, construct a bitmap context with explicit color space and alpha layout, clear/draw the background, draw source frames with aspect math, apply transition alpha/translation, then unlock with `defer`.

- [ ] **Step 4: Run compositor tests under Address Sanitizer and commit**

```bash
git add Sources/Exporting Tests/Unit/ExportFrameComposerTests.swift
git commit -m "feat: compose bounded export frames"
```

### Task 3: AVAssetWriter pipeline and cancellation

**Files:**
- Create: `Sources/Exporting/MovieWriting.swift`
- Create: `Sources/Exporting/MP4Writer.swift`
- Create: `Sources/Exporting/MovieExportCoordinator.swift`
- Create: `Tests/Integration/MP4ExportTests.swift`

**Interfaces:**
- Produces: `MovieWriting`, `MP4Writer`, `MovieExportCoordinator.start(plan:destination:progress:completion:) -> ExportCancellation`.
- Consumes: timeline and compositor.

- [ ] **Step 1: Write a two-second export integration test**

Export two colored images to a temporary 480p file. Load it with `AVAsset`; assert one video track, H.264-compatible media subtype, no audio track, expected natural size, duration within one frame, and nonzero file size.

- [ ] **Step 2: Run export test**

Expected: FAIL because writer/coordinator are undefined.

- [ ] **Step 3: Implement writer state and backpressure**

Configure `AVAssetWriterInput` and pixel-buffer adaptor, call `requestMediaDataWhenReady`, append monotonically increasing times, and finish exactly once. Convert AVFoundation failure status and error into `MovieExportError`.

- [ ] **Step 4: Add cancellation and failure tests**

Cancel after progress exceeds 10%; assert completion is `.cancelled`, the final destination is absent, and the operation-owned temporary file is removed. Inject a failing writer and assert the original destination is not replaced.

- [ ] **Step 5: Run integration tests and commit**

```bash
git add Sources/Exporting Tests/Integration
git commit -m "feat: export H264 MP4 slideshows"
```

### Task 4: Native export panel

**Files:**
- Create: `Sources/Interface/MovieExportWindowController.swift`
- Modify: `Sources/Viewer/ViewerWindowController.swift`
- Create: `Tests/UI/MovieExportSmokeTests.swift`

**Interfaces:**
- Produces: Command-E workflow for current image/current folder, presets, composition, transition, timing, background, progress, and cancellation.

- [ ] **Step 1: Write a UI smoke test for export controls**

Open a fixture, invoke Export, assert source scope, 480p/720p/1080p, Fit/Fill, Slide/Fade, duration fields, background controls, Export, and Cancel are accessibility-addressable.

- [ ] **Step 2: Run the UI test**

Expected: FAIL because the panel is missing.

- [ ] **Step 3: Build the panel with AppKit controls and validation**

Disable Export for invalid duration or inaccessible input; use `NSSavePanel` with an `.mp4` default; bind progress on the main thread; change Cancel into Close after completion; reveal a successful output only on explicit user action.

- [ ] **Step 4: Run UI and MP4 integration tests, then commit**

```bash
git add Sources/Interface Sources/Viewer Tests/UI
git commit -m "feat: add native MP4 export workflow"
```

### Task 5: Sandboxed folder provider and bookmarks

**Files:**
- Create: `Sources/FileAccess/SandboxFolderAccessProvider.swift`
- Create: `Sources/FileAccess/SecurityScopedBookmarkStore.swift`
- Create: `Tests/Unit/SecurityScopedBookmarkStoreTests.swift`
- Create: `Tests/Integration/SandboxAccessTests.swift`

**Interfaces:**
- Produces: sandbox implementation of the foundation `FolderAccessProvider` and persisted read-only folder access.

- [ ] **Step 1: Write bookmark lifecycle tests using injected URL operations**

Assert resolve/start/stop balance, stale bookmark replacement, invalid bookmark removal, longest-authorized-parent selection, and no prompt for already authorized folders.

- [ ] **Step 2: Run sandbox access tests**

Expected: FAIL because provider/store are undefined.

- [ ] **Step 3: Implement bookmark storage and access leasing**

Store bookmark data keyed by standardized folder URL. Resolve with `.withSecurityScope`; call `startAccessingSecurityScopedResource`; place the matching stop in `AccessLease`; recreate stale data using `.withSecurityScope` and `.securityScopeAllowOnlyReadAccess`.

- [ ] **Step 4: Implement deferred folder authorization UI**

Opening a Finder-provided file succeeds without a folder prompt. First adjacent navigation requests the parent folder with `NSOpenPanel`; cancellation leaves the current image visible and navigation disabled with a concise explanation.

- [ ] **Step 5: Run unit/integration tests and commit**

```bash
git add Sources/FileAccess Sources/Viewer Tests
git commit -m "feat: support sandboxed folder authorization"
```

### Task 6: Dual release configuration and localization

**Files:**
- Create: `Config/AppStore.xcconfig`
- Create: `Config/Direct.entitlements`
- Create: `Config/AppStore.entitlements`
- Create: `Resources/Base.lproj/Localizable.strings`
- Create: `Resources/zh-Hans.lproj/Localizable.strings`
- Create: `scripts/build-universal.sh`
- Create: `scripts/verify-artifact.sh`
- Modify: `LightView.xcodeproj/project.pbxproj`
- Create: `Tests/Unit/LocalizationKeyTests.swift`

**Interfaces:**
- Produces: `Release-Direct` and `Release-AppStore` artifacts with identical product features and different entitlements.

- [ ] **Step 1: Write configuration and localization assertions**

Assert every Base localization key exists in zh-Hans, Direct entitlements omit `com.apple.security.app-sandbox`, App Store entitlements set it true and include user-selected file plus app-scope bookmark access, and neither includes network client/server entitlements.

- [ ] **Step 2: Run the tests**

Expected: FAIL because the configuration files are missing.

- [ ] **Step 3: Add configuration files and runtime provider selection**

Inject `LIGHTVIEW_DISTRIBUTION_CHANNEL` as `direct` or `app-store` in Info.plist preprocessing. `AppCoordinator` constructs exactly one corresponding access provider. Keep one product name and bundle identifier because editions are not installed together.

- [ ] **Step 4: Implement deterministic separate-slice packaging**

Build x86_64 with target 10.15 and arm64 with target 11.0, combine the main executable and vendor static code with `lipo`, copy common resources once, then sign nested code and the app. The script rejects mismatched resource hashes or missing slices.

- [ ] **Step 5: Verify unsigned-equivalent release artifacts**

Run `scripts/verify-artifact.sh` on both configurations. Assert `lipo -archs` contains both architectures, `otool` shows the required per-slice minimum OS, Direct lacks sandbox entitlement, App Store contains only specified sandbox entitlements, and neither bundle contains SwiftUI/WebKit libraries.

- [ ] **Step 6: Run English/Chinese UI smoke tests and commit**

```bash
git add Config Resources scripts LightView.xcodeproj Sources/Application Tests
git commit -m "build: add direct and App Store releases"
```

