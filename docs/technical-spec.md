# LightView Technical Specification

Status: Draft for review  
Date: 2026-08-28

## 1. Architecture overview

LightView is an AppKit application written primarily in Swift. It uses small C adapters for NanoSVG and libwebp. The project uses explicit boundaries around file access, decoding, display, playback, caching, and export so that both distribution configurations share all product behavior.

The design is AppKit-oriented rather than an adaptation of a SwiftUI or SimpView structure. Window controllers coordinate native views; model and service objects contain testable behavior; decode and export work occurs outside the main thread.

```text
NSApplication / AppCoordinator
             |
      ViewerWindowController
             |
        ViewingSession
       /      |       \
FolderCatalog |    PlaybackController
              |
       ImageLoadPipeline
       /       |       \
  ImageIO    SVG     WebP
       \       |       /
          DisplayAsset
               |
        ImageCanvasView
```

## 2. Project layout

```text
LightView/
├── Config/
│   ├── Base.xcconfig
│   ├── Direct.xcconfig
│   ├── AppStore.xcconfig
│   ├── Direct.entitlements
│   └── AppStore.entitlements
├── Sources/
│   ├── Application/
│   ├── Viewer/
│   ├── Imaging/
│   ├── Canvas/
│   ├── Catalog/
│   ├── Playback/
│   ├── Exporting/
│   ├── FileAccess/
│   ├── Interface/
│   └── Preferences/
├── Vendor/
│   ├── NanoSVG/
│   └── libwebp/
├── Resources/
│   ├── Base.lproj/
│   └── zh-Hans.lproj/
├── Tests/
│   ├── Unit/
│   ├── Integration/
│   ├── Fixtures/
│   ├── UI/
│   └── Performance/
└── docs/
```

The app may use separate internal targets for `LightViewCore`, vendor C code, the application, unit tests, and UI tests. Public binary frameworks are not required.

## 3. Principal components

### 3.1 Application

`AppCoordinator` owns application-wide services, menu construction, recent documents, preferences, and the collection of viewer windows.

`ViewerWindowController` owns one window, one `ViewingSession`, one `ImageCanvasView`, and presentation of auxiliary panels. It translates AppKit responder-chain actions into session commands.

No global singleton shall own the current image. Multiple windows must remain independent, while immutable decoded assets may be shared through the cache.

### 3.2 Viewing session

`ViewingSession` is the per-window state machine. Its state includes:

- Current file URL and catalog position.
- Loading generation identifier.
- Current `DisplayAsset` or error.
- View transform: scale mode, magnification, translation, rotation, and flips.
- Animation and slideshow state.
- Current folder-access lease.

Representative states:

```text
empty -> loading -> presenting
                 -> failed
presenting -> loading(next)
presenting -> exporting (parallel read-only activity)
```

Every file change increments a generation identifier. Completion handlers discard results whose generation no longer matches the session, preventing stale decoding from replacing the requested image.

### 3.3 Folder catalog

`FolderCatalog` enumerates one directory without recursion and produces `CatalogEntry` values containing only inexpensive metadata needed for filtering and sorting.

Responsibilities:

- Skip hidden files by default.
- Filter using extension as a fast candidate check, followed by content detection during load.
- Apply locale-aware natural filename ordering.
- Support date and byte-size sorting.
- Preserve a stable tie-breaker using normalized path.
- Observe explicit reload and current-file disappearance; continuous filesystem observation may be added only if it does not create compatibility or energy regressions.

### 3.4 File access

All catalog and file reads require an `AccessLease` supplied by `FolderAccessProvider`.

```swift
protocol FolderAccessProvider {
    func accessImage(at url: URL) throws -> AccessLease
    func accessContainingFolder(of url: URL) throws -> AccessLease
    func restorePersistedAccess(to url: URL) throws -> AccessLease?
}
```

`DirectFolderAccessProvider` validates ordinary filesystem readability and returns a lightweight lease.

`SandboxFolderAccessProvider`:

- Uses implicit access supplied by Finder, drag and drop, or `NSOpenPanel` for the selected item.
- Resolves read-only security-scoped bookmarks for known directories.
- Requests a directory with `NSOpenPanel` when adjacent navigation needs broader access.
- Balances every successful `startAccessingSecurityScopedResource()` with exactly one stop call owned by the lease.
- Refreshes stale bookmarks and removes invalid ones.

The App Store entitlement permits user-selected read/write access because `NSSavePanel` must create MP4 output, but viewing code opens source files read-only.

### 3.5 Format detection and decode routing

`FileSignatureDetector` reads a bounded prefix and identifies known containers using magic values. Extension and Uniform Type Identifier information are advisory.

`ImageLoadPipeline` performs:

1. File-access validation.
2. Header and metadata inspection.
3. Decoder selection.
4. Target raster calculation from viewport, backing scale, and zoom intent.
5. Background decode.
6. Color and orientation normalization.
7. Publication of an immutable `DisplayAsset`.

Decoder order:

```text
SVG signature/structure       -> SVGDecoder
RIFF WEBP                     -> ImageIO if accepted, otherwise WebPDecoder
AVIF/AVIS                     -> ImageIO on macOS 13+, otherwise unsupported
Other recognized image data  -> ImageIODecoder
Unknown                       -> unsupported
```

The pipeline shall not use an ImageIO property constant on an OS older than that constant's availability. Runtime decoder success remains authoritative.

### 3.6 Display assets

```swift
enum DisplayAsset {
    case raster(RasterAsset)
    case animation(AnimationAsset)
    case vector(VectorAsset)
}
```

`RasterAsset` contains the decoded `CGImage`, original pixel dimensions, decoded dimensions, orientation, color-profile description, and source metadata.

`AnimationAsset` contains canvas dimensions, frame count, loop behavior, a frame provider, and normalized timing information. It does not require all frames to be resident.

`VectorAsset` retains a safe parsed path model and can rasterize for a requested output size.

Display assets are immutable after publication. Mutable playback position belongs to the session.

### 3.7 ImageIO decoder

The decoder shall:

- Set caching options deliberately instead of relying on defaults.
- Read properties before creating a raster.
- Apply embedded orientation exactly once.
- Create downsampled thumbnails for fit/fill presentation using the viewport's pixel demand.
- Preserve ICC color information and allow ColorSync-backed display conversion.
- Decode full resolution only when zoom demand exceeds the available raster and the memory budget permits it.
- Return animation frame metadata for ImageIO-supported GIF, APNG, and WebP.

### 3.8 SVG decoder and renderer

NanoSVG source is vendored at a pinned version with its license. A C adapter exposes only owned opaque parse handles and plain data required by Swift.

Before parsing, LightView rejects oversized source files according to a configurable safety ceiling and disables external resource resolution. The renderer converts supported paths and paints into Core Graphics operations.

Vector content is retained while visible. Raster cache keys include source identity, target pixel dimensions, display scale, and appearance-dependent background inputs.

### 3.9 WebP decoder

`libwebp` is compiled as static, decoder-only Universal 2 code with dead stripping enabled.

The adapter supports:

- Header validation and feature discovery.
- Decode directly into an allocated BGRA buffer with checked row-byte arithmetic.
- Decoder-side scaling for preview-sized output when supported.
- ICC, EXIF, and XMP extraction.
- Animation demux, frame offsets, blend/disposal flags, durations, and loop count.
- Strict upper bounds on dimensions, frame count, allocation size, and duration.

All C allocations are owned by scoped Swift wrapper objects and released on cancellation or deinitialization.

### 3.10 Canvas

`ImageCanvasView` is a layer-backed `NSView`. It owns no file or decoder state.

It receives a display asset plus a `ViewportState` and is responsible for:

- Computing destination geometry.
- Drawing the current raster or animation frame.
- Applying rotation and flips without rewriting pixels where possible.
- Handling backing-scale and color-space changes.
- Mapping pointer and gesture coordinates into image coordinates.
- Emitting semantic zoom, pan, and navigation intentions.

`ViewportGeometry` is a value-type math component tested independently from AppKit events. It defines fit, fill, actual-size, anchor-preserving zoom, panning bounds, rotation-aware dimensions, and Retina conversions.

Integral zoom levels use nearest-neighbor filtering when pixel-sharp mode is active. Reduction and fractional zoom use high-quality interpolation.

### 3.11 Cache and memory budget

`RasterCache` uses a decoded-cost limit. Cost is calculated with overflow-checked multiplication of row bytes and height, plus known frame and vector-model costs.

Initial policy:

- Metadata entries: bounded count with low cost.
- Current display raster: retained while visible.
- Neighbor previews: at most the configured one or two neighbors.
- Full-resolution rasters: normally current image only.
- Animation frames: sliding window around playback position.
- Memory-pressure event: immediately remove neighbors, animation history, and nonvisible full-resolution data.

The default cache budget is selected from physical memory but capped to prevent a lightweight viewer from consuming an excessive fraction of RAM. The exact formula will be finalized by performance tests and recorded in the implementation plan.

### 3.12 Playback

`FrameClock` uses a monotonic time source and schedules presentation based on accumulated target timestamps rather than chaining frame-duration delays. This prevents long-term drift.

Late frames may be skipped to catch up, but frame composition state must remain correct. Minimum frame-duration normalization is format-specific and tested against fixtures.

`SlideshowController` is separate from animated-image playback. It requests navigation commands at the selected interval and suspends while modal panels or export setup require attention.

### 3.13 MP4 export

`MovieExportCoordinator` converts an immutable `MovieExportPlan` into an H.264 MP4 file.

Components:

- `ExportTimelineBuilder`: converts sources, durations, animation policies, and transitions into frame instructions.
- `ExportFrameComposer`: draws background, fit/fill image content, and transition state into a reusable pixel-buffer pool.
- `MP4Writer`: owns `AVAssetWriter`, `AVAssetWriterInput`, and `AVAssetWriterInputPixelBufferAdaptor`.
- `ExportProgress`: thread-safe progress and cancellation state.

The export pipeline is bounded: it composes and submits one small group of frames at a time and does not retain the complete output timeline as raster images.

Temporary files are created beside the selected destination when permitted or inside the application temporary directory, then atomically moved to the final destination after successful completion. Cancellation removes only the temporary output owned by the export operation.

### 3.14 Interface and preferences

Interface controllers are conventional AppKit controllers:

- `WelcomeViewController`
- `PreferencesWindowController`
- `ImageInfoWindowController`
- `MovieExportWindowController`

The welcome keyboard map is built from the same immutable `CommandCatalog` used to construct menus, preventing documentation and menu shortcuts from diverging.

Preferences are stored in `UserDefaults` using typed keys and validated ranges. Direct and App Store editions use the same schema, though their containers may store values separately.

## 4. Concurrency model

The minimum OS predates modern Swift concurrency deployment as a universally simple baseline, so version 1 shall use Foundation concurrency primitives that work reliably on macOS 10.15:

- `OperationQueue` for cancellable decode and catalog work.
- A serial coordination queue for cache mutation.
- `DispatchQueue` for small asynchronous work and main-thread delivery.
- AppKit access only on the main thread.

The design shall not require SwiftUI, Combine, actors, or an async/await application architecture. Modern language features may be used only when their back-deployment and runtime effects have been verified.

## 5. Build and compatibility

### 5.1 Architecture slices

- x86_64 slice deployment target: macOS 10.15.
- arm64 slice deployment target: macOS 11.0.
- Release artifacts are checked with `lipo`, `file`, and `otool`.

If Xcode cannot express different per-architecture deployment targets in one build action reliably, the release script shall build slices separately and combine only the main executable and compatible static vendor libraries in a deterministic packaging step.

### 5.2 Configuration differences

`Release-Direct`:

- App Sandbox entitlement absent.
- Hardened Runtime enabled.
- Developer ID signing and notarization validation.

`Release-AppStore`:

- `com.apple.security.app-sandbox = true`.
- User-selected file access enabled.
- App-scoped bookmarks enabled.
- No network entitlement.
- Mac App Store signing and provisioning.

Feature code shall not be selected by scattered compiler checks. One build-defined distribution value selects the `FolderAccessProvider`; all other behavior remains common.

## 6. Error handling

Errors are mapped into user-facing categories while preserving diagnostic causes for logs:

- Access denied or folder authorization required.
- File missing or changed during load.
- Unsupported format or unsupported on this macOS version.
- Damaged or truncated content.
- Image dimensions or allocation exceed safety limits.
- Decode cancelled.
- MP4 destination, encoder, disk-space, or cancellation failure.

Expected file and decode failures shall not terminate the application or leave a stale image labeled as the new file.

## 7. Test specification

### 7.1 Unit tests

- File signatures, including misleading extensions.
- Natural sorting and stable tie-breaking.
- Catalog navigation and wrapping.
- Fit, fill, actual size, rotation, flip, pan bounds, and pointer-anchored zoom math.
- Checked raster-cost arithmetic and cache eviction.
- Generation-based stale-result rejection.
- GIF/APNG/WebP duration and loop normalization.
- Slideshow state transitions.
- Export timeline and transition interpolation.
- Preference validation and migration.
- Security-scoped lease balancing using test doubles.

### 7.2 Decoder fixture tests

Fixtures shall cover:

- JPEG: EXIF orientations, ICC profiles, grayscale, CMYK, progressive and truncated.
- PNG: alpha, indexed color, 16-bit, interlaced, APNG.
- GIF: disposal modes, transparency, short delays, finite and infinite looping.
- TIFF: multipage and high bit depth where ImageIO supports it.
- HEIC/HEIF and representative RAW files where fixtures may be redistributed.
- WebP: lossy, lossless, alpha, ICC, animated disposal/blending, malformed and oversized headers.
- SVG: paths, transforms, viewBox, gradients, unsupported features, external references, entity abuse, and malformed XML.
- AVIF: native success on macOS 13+ and explicit unsupported behavior on macOS 10.15 through 12.

Golden-image comparisons shall use defined tolerances for decoder and color-management differences rather than requiring byte-identical pixels across all macOS releases.

### 7.3 Integration tests

- Open through File menu, Finder event simulation, recent documents, and drag/drop.
- Folder enumeration and adjacent navigation.
- Fast repeated navigation cancels stale work.
- Multiple windows remain independent.
- Background/foreground animation energy behavior.
- Direct folder access without a permission prompt.
- App Store single-file access followed by folder authorization and bookmark restoration.
- MP4 export for static images, mixed dimensions, transparency, animated input, both transitions, cancellation, and invalid destination.

### 7.4 UI smoke tests

- First-launch welcome view.
- Fixed shortcut behavior and menu enablement.
- Full screen, appearance changes, Retina scale changes, and multiple screens.
- Preferences and information windows.
- Accessibility names and keyboard traversal.
- English and Simplified Chinese layouts.

### 7.5 Performance tests

The benchmark harness records bundle size, main Mach-O size, launch latency, first-frame latency, median RSS, peak RSS, and relevant child processes.

Scenarios:

1. Empty window after launch.
2. Small reference JPEG.
3. 12000 x 8000 reference JPEG fit to window.
4. The same large JPEG at actual size.
5. Rapid traversal of 100 mixed files.
6. Large animated GIF and animated WebP.
7. SVG with many paths.
8. 1080p MP4 export.

Each comparison run uses the same files, settle time, foreground state, run count, and launch order for LightView, qView, Tovi, and SimpView. Multi-process applications are measured with attributable helper-process deltas as well as main-process RSS. Results include the limitations of RSS summation.

### 7.6 Compatibility tests

Required release coverage:

- Intel macOS 10.15 on physical Intel hardware or a verified Intel virtual machine.
- Latest supported Intel macOS available to the test fleet.
- Apple silicon macOS 11 on compatible physical hardware or a verified environment.
- Current Apple silicon macOS.
- Direct and App Store configurations on each applicable architecture.

Compiler availability checks do not replace at least one real Intel 10.15 launch-and-view test before release.

## 8. Third-party code policy

- NanoSVG and libwebp are pinned to reviewed versions.
- Only required source files and decoder features are built.
- License texts and version information are included in the application acknowledgements and repository documentation.
- Dependency updates require decoder fixture tests, malformed-input tests, size comparison, and performance comparison.
- No qView, Tovi, or SimpView source is copied into LightView.

## 9. Documentation deliverables

The final README shall contain:

- Product purpose and screenshots.
- Supported systems and formats, including AVIF's macOS 13 requirement.
- Fixed shortcuts and gestures.
- Direct versus App Store folder-access behavior.
- Build, test, signing, and release instructions.
- Privacy statement.
- Third-party acknowledgements.
- Reproducible performance method and a comparison table for LightView, qView, Tovi, and SimpView.

