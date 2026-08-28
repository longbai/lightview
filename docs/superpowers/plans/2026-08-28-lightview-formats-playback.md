# LightView Formats and Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe static SVG, static/animated WebP, ImageIO animations, accurate playback, and folder slideshow behavior to the working native viewer.

**Architecture:** Format adapters publish the same immutable display-asset model as ImageIO. Animation composition is separated from clock state; slideshow timing issues navigation commands rather than manipulating the canvas directly.

**Tech Stack:** Swift, Core Graphics, ImageIO, XCTest, NanoSVG commit `239e102ec2c691f2902e20ace2ed36ee4a35cfe6`, libwebp v1.6.0 commit `4fa21912338357f89e4fd51cf2368325b59e9bd9`.

**Spec:** `docs/requirements.md` and `docs/technical-spec.md`

## Global Constraints

- Vendor only reviewed decoder source required by LightView and include licenses.
- Never execute SVG scripts or load external SVG resources.
- Prefer ImageIO at runtime for WebP; use libwebp only when native decode is unavailable or fails.
- AVIF remains native-only on macOS 13+.
- Animation memory is bounded by decoded byte cost.

---

### Task 1: Safe SVG adapter and Core Graphics renderer

**Files:**
- Create: `.gitmodules`
- Create: `Vendor/NanoSVG/upstream/` as a submodule pinned to `239e102ec2c691f2902e20ace2ed36ee4a35cfe6`
- Create: `Vendor/NanoSVG/LightViewSVGAdapter.h`
- Create: `Vendor/NanoSVG/LightViewSVGAdapter.c`
- Create: `Vendor/DEPENDENCIES.md`
- Create: `Sources/Imaging/SVGDecoder.swift`
- Create: `Tests/Unit/SVGDecoderTests.swift`
- Create: `Tests/Fixtures/SVG/basic.svg`
- Create: `Tests/Fixtures/SVG/external-resource.svg`
- Modify: `LightView.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `SVGDecoder.inspect(url:)` and `decode(_:) -> DisplayAsset`.
- Consumes: imaging types and decoder protocol from the foundation plan.

- [ ] **Step 1: Add the pinned parser and verify it in a scriptable manifest**

Run `git submodule add https://github.com/memononen/nanosvg.git Vendor/NanoSVG/upstream`, checkout commit `239e102ec2c691f2902e20ace2ed36ee4a35cfe6`, and commit the gitlink. Record repository URL, commit, `src/nanosvg.h` path, header SHA-256, and zlib license in `Vendor/DEPENDENCIES.md`. Expose adapter functions for parse, width/height, safe path iteration, and destruction; Swift never imports NanoSVG structs directly.

- [ ] **Step 2: Write failing SVG behavior and security tests**

Assert `basic.svg` reports its viewBox, renders nontransparent pixels at 64x64, respects a transform, and rejects an external image URL. Assert a configured source-byte ceiling rejects oversized input before parsing.

- [ ] **Step 3: Run SVG tests**

Expected: FAIL because `SVGDecoder` is undefined.

- [ ] **Step 4: Implement parsing and Core Graphics drawing**

Map paths to `CGMutablePath`, preserve fill/stroke/opacity and supported gradients, flip SVG coordinates once for Core Graphics, and render only to the requested pixel size. Convert unsupported external references to `ImageLoadError.unsafeExternalResource`.

- [ ] **Step 5: Run SVG tests, Address Sanitizer tests, and full unit tests**

Expected: PASS without leaks or out-of-bounds findings on malformed fixtures.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules Vendor Sources/Imaging/SVGDecoder.swift Tests LightView.xcodeproj
git commit -m "feat: render safe static SVG"
```

### Task 2: Decoder-only libwebp adapter

**Files:**
- Modify: `.gitmodules`
- Create: `Vendor/libwebp/upstream/` as a submodule pinned to `4fa21912338357f89e4fd51cf2368325b59e9bd9`
- Create: `Vendor/libwebp/LightViewWebPAdapter.h`
- Create: `Vendor/libwebp/LightViewWebPAdapter.c`
- Create: `scripts/build-libwebp.sh`
- Create: `Sources/Imaging/WebPDecoder.swift`
- Create: `Tests/Unit/WebPDecoderTests.swift`
- Create: `Tests/Fixtures/WebP/static-lossy.webp`
- Create: `Tests/Fixtures/WebP/static-alpha.webp`
- Modify: `LightView.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `WebPDecoder.inspect(url:)` and `decode(_:) -> DisplayAsset` plus internal animation frame access used by Task 4.

- [ ] **Step 1: Add the pinned upstream source and decoder-only build settings**

Run `git submodule add https://chromium.googlesource.com/webm/libwebp Vendor/libwebp/upstream`, checkout peeled v1.6.0 commit `4fa21912338357f89e4fd51cf2368325b59e9bd9`, and commit the gitlink. `scripts/build-libwebp.sh` configures upstream CMake separately for x86_64/macOS 10.15 and arm64/macOS 11.0 with `-DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_LIBWEBPMUX=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_WEBP_JS=OFF -DWEBP_BUILD_FUZZTEST=OFF -DWEBP_ENABLE_SIMD=ON -DCMAKE_C_FLAGS_RELEASE='-Os -fvisibility=hidden'`. Build only targets `webpdecoder` and `webpdemux`, producing deterministic archives under `build/vendor/<arch>/`. Record the tag, peeled commit, license, CMake arguments, archive hashes, and linked object list in `Vendor/DEPENDENCIES.md`.

- [ ] **Step 2: Write failing static WebP tests**

Assert dimensions, alpha preservation, decoder-side target scaling, invalid RIFF rejection, checked allocation limits, and cancellation cleanup.

- [ ] **Step 3: Run WebP tests**

Expected: FAIL because adapter functions are missing.

- [ ] **Step 4: Implement the C ownership boundary and Swift decoder**

Return BGRA into a caller-owned buffer with validated width, height, and row bytes. Wrap allocated buffers with a single release closure. Preserve ICC bytes for Core Graphics color-space construction when valid.

- [ ] **Step 5: Make decode routing native-first**

For `RIFF WEBP`, call ImageIO first. Fall back only when source creation or requested frame decode fails. Add a spy-based routing test that proves native success skips the fallback and native failure invokes it once.

- [ ] **Step 6: Run unit and sanitizer tests, then commit**

```bash
git add .gitmodules Vendor scripts/build-libwebp.sh Sources/Imaging Tests LightView.xcodeproj
git commit -m "feat: add bounded WebP fallback decoding"
```

### Task 3: Animation model and monotonic frame clock

**Files:**
- Modify: `Sources/Imaging/ImageTypes.swift`
- Create: `Sources/Playback/FrameClock.swift`
- Create: `Sources/Playback/AnimationController.swift`
- Create: `Tests/Unit/FrameClockTests.swift`
- Create: `Tests/Unit/AnimationControllerTests.swift`

**Interfaces:**
- Produces: `AnimationDescriptor`, `AnimationFrameProvider`, `FrameClock.advance(to:)`, and `AnimationController` play/pause/speed/frame commands.

- [ ] **Step 1: Write deterministic timing tests with a fake monotonic clock**

Use frame durations `[0.10, 0.20, 0.30]`; assert exact indices at accumulated times, finite loop completion, infinite wrapping, 2x speed, pause stability, and late-frame catch-up without timeline drift.

- [ ] **Step 2: Run playback tests**

Expected: FAIL because animation types are undefined.

- [ ] **Step 3: Implement immutable descriptors and timestamp-based advancement**

Store normalized positive durations and cumulative boundaries. Calculate presentation from elapsed monotonic time rather than scheduling chained delays. Keep playback position in `AnimationController`, never in `AnimationAsset`.

- [ ] **Step 4: Add a bounded sliding frame cache**

Retain current, next, and one prior composited frame within the raster budget. Evict prior frames first under pressure. Add tests proving a 3-frame budget never retains 4 frames.

- [ ] **Step 5: Run all tests and commit**

```bash
git add Sources/Imaging/ImageTypes.swift Sources/Playback Tests/Unit
git commit -m "feat: add deterministic animation playback"
```

### Task 4: GIF, APNG, and animated WebP composition

**Files:**
- Create: `Sources/Imaging/ImageIOAnimationDecoder.swift`
- Create: `Sources/Imaging/WebPAnimationDecoder.swift`
- Create: `Sources/Imaging/FrameCompositor.swift`
- Create: `Tests/Unit/AnimationDecoderTests.swift`
- Create: `Tests/Fixtures/Animation/disposal.gif`
- Create: `Tests/Fixtures/Animation/sample.apng`
- Create: `Tests/Fixtures/Animation/blend.webp`

**Interfaces:**
- Produces: animation `DisplayAsset` values whose frame providers return correctly composited `CGImage` frames.
- Consumes: WebP adapter, ImageIO properties, `AnimationDescriptor`, and raster cache.

- [ ] **Step 1: Write fixture tests for timing, disposal, alpha, and looping**

Assert exact canvas pixels at selected frame coordinates, normalized duration values, finite/infinite loop behavior, and no full-frame-array allocation at asset creation.

- [ ] **Step 2: Run animation decoder tests**

Expected: FAIL because decoders/compositor are missing.

- [ ] **Step 3: Implement ImageIO animation metadata and lazy frame decode**

Read GIF/APNG/WebP dictionaries only behind availability guards. Normalize absent/invalid delays with documented format rules. Keep source data mapped/read-only while visible and decode frames on demand.

- [ ] **Step 4: Implement WebP demux composition**

Apply frame offsets, blend flags, disposal-to-background, alpha, duration, and loop count onto a reusable canvas. Use checked dimensions before allocation.

- [ ] **Step 5: Connect animation controls to window commands and canvas**

Space toggles playback; menu commands pause, step, and adjust speed. Window occlusion suspends the display timer when energy saving is enabled.

- [ ] **Step 6: Run all tests and commit**

```bash
git add Sources Tests LightView.xcodeproj
git commit -m "feat: display native animated images"
```

### Task 5: Folder slideshow

**Files:**
- Create: `Sources/Playback/SlideshowController.swift`
- Create: `Tests/Unit/SlideshowControllerTests.swift`
- Modify: `Sources/Viewer/ViewingSession.swift`
- Modify: `Sources/Viewer/ViewerWindowController.swift`

**Interfaces:**
- Produces: `SlideshowController.start(direction:interval:)`, `pause`, `resume`, and `stop`.
- Consumes: session navigation closure and monotonic scheduler abstraction.

- [ ] **Step 1: Write scheduler-driven slideshow tests**

Assert forward/reverse navigation, pause/resume without duplicate timers, wrapping preference, manual-navigation cancellation, and interval validation.

- [ ] **Step 2: Run slideshow tests**

Expected: FAIL because controller is undefined.

- [ ] **Step 3: Implement a single-owner timer state machine**

Use one dispatch timer or injected test scheduler. Reschedule only after state changes; cancel it on session/window teardown. Emit navigation commands rather than accessing files or canvas state.

- [ ] **Step 4: Integrate Return shortcut, menus, and full-screen behavior**

Update menu checked/enabled states from controller state. Ensure modal Open/Export panels suspend slideshow and restore only when it was previously active.

- [ ] **Step 5: Run the Plan 2 gate and commit**

Run unit/UI tests, sanitizer decoder tests, static SVG/WebP manual viewing, animated fixture playback, and a 20-image slideshow.

```bash
git add Sources Tests
git commit -m "feat: add folder slideshow"
```

### Task 6: Native AVIF policy and format reporting

**Files:**
- Create: `Sources/Imaging/NativeFormatPolicy.swift`
- Create: `Tests/Unit/NativeFormatPolicyTests.swift`
- Modify: `Sources/Imaging/ImageLoadPipeline.swift`
- Modify: `Sources/Interface/ImageInfoWindowController.swift`

**Interfaces:**
- Produces: injected `NativeFormatPolicy.canAttemptAVIF(on:)` and explicit unsupported-system errors.
- Consumes: AVIF signature detection and ImageIO decoder.

- [ ] **Step 1: Write version-policy and fallback tests**

Assert macOS 10.15, 11, and 12 return an AVIF unsupported-system result without calling ImageIO; macOS 13+ attempts ImageIO; a native failure on 13+ becomes damaged/unsupported content and never invokes libwebp or another external decoder.

- [ ] **Step 2: Run the policy tests**

Expected: FAIL because `NativeFormatPolicy` is undefined.

- [ ] **Step 3: Implement the availability-isolated route**

Keep AVIF-specific ImageIO property access inside `if #available(macOS 13.0, *)`. Use injected `OperatingSystemVersion` only for pure policy tests; production decoder success remains authoritative. Present “AVIF requires macOS 13 or later” on older systems and show the same limitation in the information/help interface.

- [ ] **Step 4: Run Plan 2 verification and commit**

Run all format, animation, slideshow, UI, and sanitizer tests on the current system; compile the x86_64 10.15 and arm64 11.0 variants.

```bash
git add Sources/Imaging Sources/Interface Tests/Unit
git commit -m "feat: enforce native-only AVIF support"
```
