# LightView Native Viewer Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working AppKit LightView that opens and navigates static ImageIO images with bounded decoding, native zoom/pan, menus, and a welcome guide.

**Architecture:** A small AppKit application target depends on a testable `LightViewCore` target. Per-window `ViewingSession` coordinates access, catalog, decode, and immutable display assets. `ImageCanvasView` renders assets but never reads files.

**Tech Stack:** Swift, AppKit, Foundation, ImageIO, Core Graphics, QuartzCore, XCTest, native Xcode project.

**Spec:** `docs/requirements.md` and `docs/technical-spec.md`

## Global Constraints

- AppKit only; no SwiftUI, WebKit, Combine-based architecture, or copied comparison-project code.
- x86_64 deployment target is macOS 10.15; arm64 release slice target is macOS 11.0.
- Static-image work is off the main thread and cancellation-aware.
- Source files are never modified.
- Every behavior starts with a failing XCTest.

---

## File map

- `LightView.xcodeproj/project.pbxproj`: native application, core, unit-test, and UI-test targets.
- `Config/Base.xcconfig`: shared compiler warnings, Swift version, bundle metadata, deployment defaults.
- `Config/Debug.xcconfig`: debug-only diagnostics.
- `Config/Direct.xcconfig`: non-sandbox Direct build selection.
- `Sources/Application/main.swift`: AppKit entry point.
- `Sources/Application/AppDelegate.swift`: application lifecycle.
- `Sources/Application/AppCoordinator.swift`: windows, menus, recent documents.
- `Sources/Core/ProductIdentity.swift`: product constants shared by the app and tests.
- `Sources/Viewer/ViewingSession.swift`: per-window state and generation checks.
- `Sources/Viewer/ViewerWindowController.swift`: responder actions and view binding.
- `Sources/Catalog/FolderCatalog.swift`: nonrecursive file list and sorting.
- `Sources/FileAccess/FolderAccessProvider.swift`: access contracts and leases.
- `Sources/FileAccess/DirectFolderAccessProvider.swift`: ordinary filesystem access.
- `Sources/Imaging/FileSignatureDetector.swift`: bounded header detection.
- `Sources/Imaging/ImageTypes.swift`: metadata, requests, assets, errors.
- `Sources/Imaging/ImageIODecoder.swift`: metadata, thumbnail, and full raster decoding.
- `Sources/Imaging/ImageLoadPipeline.swift`: decoder orchestration and cancellation.
- `Sources/Imaging/RasterCache.swift`: decoded-byte accounting and eviction.
- `Sources/Canvas/ViewportGeometry.swift`: pure transform math.
- `Sources/Canvas/ImageCanvasView.swift`: layer-backed AppKit rendering and events.
- `Sources/Interface/WelcomeViewController.swift`: first-launch shortcut/gesture view.
- `Sources/Interface/PreferencesWindowController.swift`: native settings window.
- `Sources/Interface/ImageInfoWindowController.swift`: current-file information window.
- `Sources/Preferences/PreferencesStore.swift`: typed validated defaults.
- `Sources/Preferences/CommandCatalog.swift`: fixed menu and welcome shortcuts.
- `Tests/Unit/*Tests.swift`: focused unit tests.
- `Tests/Fixtures/Static/*`: redistributable image fixtures.

### Task 1: Native project and test harness

**Files:**
- Create: `LightView.xcodeproj/project.pbxproj`
- Create: `Config/Base.xcconfig`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Direct.xcconfig`
- Create: `Resources/Info.plist`
- Create: `Sources/Application/main.swift`
- Create: `Sources/Application/AppDelegate.swift`
- Create: `Sources/Application/AppCoordinator.swift`
- Create: `Sources/Core/ProductIdentity.swift`
- Create: `Sources/Viewer/ViewerWindowController.swift`
- Create: `Tests/Unit/BootstrapTests.swift`

**Interfaces:**
- Produces: `AppCoordinator.makeWindowController() -> ViewerWindowController` and buildable `LightView`, `LightViewCore`, `LightViewTests`, `LightViewUITests` schemes/targets.

- [ ] **Step 1: Create the native project and a failing bootstrap test**

Configure `SWIFT_VERSION = 6.0`, `MACOSX_DEPLOYMENT_TARGET = 10.15`, `CLANG_ENABLE_MODULES = YES`, `SWIFT_STRICT_CONCURRENCY = targeted`, warnings as errors for LightView-owned source, and `PRODUCT_BUNDLE_IDENTIFIER = app.lightview.LightView`. Add this test:

```swift
import XCTest
@testable import LightViewCore

final class BootstrapTests: XCTestCase {
    func testProductIdentity() {
        XCTAssertEqual(ProductIdentity.name, "LightView")
        XCTAssertEqual(ProductIdentity.minimumIntelSystem, OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0))
    }
}
```

- [ ] **Step 2: Run the test and verify the missing type failure**

Run: `xcodebuild -project LightView.xcodeproj -scheme LightView -configuration Debug -derivedDataPath build/LightViewDerived test`

Expected: FAIL because `ProductIdentity` is undefined.

- [ ] **Step 3: Add the minimum bootstrap implementation**

Create `Sources/Core/ProductIdentity.swift` in the `LightViewCore` target:

```swift
import Foundation

public enum ProductIdentity {
    public static let name = "LightView"
    public static let minimumIntelSystem = OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)
}
```

Use `NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)` in `main.swift`. `AppDelegate.applicationDidFinishLaunching` creates `AppCoordinator` and opens an empty `ViewerWindowController`. Its initial content is a centered native `NSTextField` reading “Open an image or folder”; Task 8 replaces that content with the complete welcome and canvas interface.

- [ ] **Step 4: Run tests and launch the empty application**

Run the test command above, then:

`xcodebuild -project LightView.xcodeproj -scheme LightView -configuration Debug -derivedDataPath build/LightViewDerived build`

Expected: tests PASS and `build/LightViewDerived/Build/Products/Debug/LightView.app` launches without a crash.

- [ ] **Step 5: Commit**

```bash
git add LightView.xcodeproj Config Resources Sources/Application Sources/Core Sources/Viewer/ViewerWindowController.swift Tests/Unit/BootstrapTests.swift
git commit -m "build: create native LightView project"
```

### Task 2: Format signatures and immutable image types

**Files:**
- Create: `Sources/Imaging/FileSignatureDetector.swift`
- Create: `Sources/Imaging/ImageTypes.swift`
- Create: `Tests/Unit/FileSignatureDetectorTests.swift`

**Interfaces:**
- Produces: `ImageFormat`, `ImageMetadata`, `RasterAsset`, `DisplayAsset`, `DecodeRequest`, `ImageLoadError`, and `FileSignatureDetector.detect(_:)`.

- [ ] **Step 1: Write signature tests**

```swift
func testDetectsMagicInsteadOfExtension() {
    XCTAssertEqual(FileSignatureDetector.detect(Data([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A])), .png)
    XCTAssertEqual(FileSignatureDetector.detect(Data("RIFF1234WEBPVP8 ".utf8)), .webP)
    XCTAssertEqual(FileSignatureDetector.detect(Data("<svg viewBox='0 0 1 1'>".utf8)), .svg)
}

func testRejectsShortOrUnknownHeaders() {
    XCTAssertNil(FileSignatureDetector.detect(Data()))
    XCTAssertNil(FileSignatureDetector.detect(Data([0x00, 0x01, 0x02])))
}
```

- [ ] **Step 2: Run only the new test class**

Run: `xcodebuild -project LightView.xcodeproj -scheme LightView -derivedDataPath build/LightViewDerived test -only-testing:LightViewTests/FileSignatureDetectorTests`

Expected: FAIL because detector and types do not exist.

- [ ] **Step 3: Implement bounded signature detection and value types**

Define `ImageFormat` cases `jpeg`, `png`, `gif`, `tiff`, `bmp`, `ico`, `jpeg2000`, `heif`, `webP`, `svg`, `avif`, `unknown`. Inspect at most 512 bytes; trim a UTF-8 BOM and leading ASCII whitespace only for SVG. Define `DecodeRequest(url:targetPixelSize:requiresFullResolution:generation:)` and immutable asset structs holding `CGImage`, original and decoded sizes, orientation, metadata, and decoded byte cost.

- [ ] **Step 4: Run detector tests and the full suite**

Expected: all tests PASS with no warning promoted to error.

- [ ] **Step 5: Commit**

```bash
git add Sources/Imaging Tests/Unit/FileSignatureDetectorTests.swift
git commit -m "feat: add image signatures and asset types"
```

### Task 3: Folder catalog and navigation

**Files:**
- Create: `Sources/Catalog/FolderCatalog.swift`
- Create: `Tests/Unit/FolderCatalogTests.swift`

**Interfaces:**
- Produces: `CatalogSort`, `CatalogEntry`, `FolderCatalog.entries`, `index(of:)`, and `neighbor(from:direction:wraps:)`.

- [ ] **Step 1: Write tests using a temporary folder**

Create `img2.png`, `img10.png`, `.hidden.png`, and `notes.txt`. Assert natural order is `img2.png`, `img10.png`; hidden and unsupported candidates are excluded; previous/next boundaries obey `wraps`.

- [ ] **Step 2: Run the catalog tests**

Expected: FAIL because `FolderCatalog` is undefined.

- [ ] **Step 3: Implement nonrecursive enumeration and stable sorting**

Use `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` with keys for regular-file status, hidden status, dates, and byte size. Compare names with `.numeric`, `.caseInsensitive`, and `.localized`; use normalized path as final tie-breaker. Do not open full file contents during enumeration.

- [ ] **Step 4: Run catalog and full unit tests**

Expected: PASS, including empty directory and removed-current-file cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/Catalog Tests/Unit/FolderCatalogTests.swift
git commit -m "feat: add deterministic folder catalog"
```

### Task 4: File-access lease abstraction

**Files:**
- Create: `Sources/FileAccess/FolderAccessProvider.swift`
- Create: `Sources/FileAccess/DirectFolderAccessProvider.swift`
- Create: `Tests/Unit/FolderAccessProviderTests.swift`

**Interfaces:**
- Produces: `AccessLease`, `FolderAccessProvider`, and `DirectFolderAccessProvider` matching the technical specification signatures.
- Consumes: local URLs from `FolderCatalog`.

- [ ] **Step 1: Write lifecycle and denial tests**

Assert a lease runs its release closure exactly once even when `end()` and deinitialization both occur. Assert Direct access rejects a missing file and accepts a readable temporary directory.

- [ ] **Step 2: Run the access tests**

Expected: FAIL because access types are undefined.

- [ ] **Step 3: Implement idempotent lease ownership**

Protect lease ending with `NSLock`; expose `url` and `end()`. Direct provider validates `isReadableFile(atPath:)` and directory resource values, returning `.accessDenied` or `.missing` errors with the original URL.

- [ ] **Step 4: Run access and full unit tests**

Expected: PASS and no double-release count.

- [ ] **Step 5: Commit**

```bash
git add Sources/FileAccess Tests/Unit/FolderAccessProviderTests.swift
git commit -m "feat: isolate folder access policy"
```

### Task 5: Viewport geometry

**Files:**
- Create: `Sources/Canvas/ViewportGeometry.swift`
- Create: `Tests/Unit/ViewportGeometryTests.swift`

**Interfaces:**
- Produces: `ViewportMode`, `ViewportState`, `ViewportGeometry.fitScale`, `fillScale`, `anchoredZoom`, `clampedTranslation`, and `displayedSize`.

- [ ] **Step 1: Write exact geometry tests**

Test a 4000x2000 image in a 1000x1000 viewport: fit is 0.25, fill is 0.5, 90-degree rotation swaps displayed dimensions, actual size accounts for backing scale, and zooming around `(250, 300)` preserves the image-space point beneath that anchor.

- [ ] **Step 2: Run geometry tests**

Expected: FAIL because geometry functions are undefined.

- [ ] **Step 3: Implement pure CGFloat math**

Normalize rotation to `0`, `90`, `180`, or `270`; reject nonfinite and nonpositive sizes; clamp magnification to `0.01...128`; center axes smaller than the viewport and clamp larger axes so blank space cannot be dragged across the viewport.

- [ ] **Step 4: Run geometry tests in both architectures' compile modes**

Run unit tests normally, then build core with `ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=10.15`.

Expected: tests PASS and x86_64 compilation succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/Canvas Tests/Unit/ViewportGeometryTests.swift
git commit -m "feat: define tested viewport geometry"
```

### Task 6: ImageIO decoder and raster cache

**Files:**
- Create: `Sources/Imaging/ImageDecoding.swift`
- Create: `Sources/Imaging/ImageIODecoder.swift`
- Create: `Sources/Imaging/RasterCache.swift`
- Create: `Tests/Unit/ImageIODecoderTests.swift`
- Create: `Tests/Unit/RasterCacheTests.swift`
- Create: `Tests/Fixtures/Static/oriented-6.jpg`
- Create: `Tests/Fixtures/Static/alpha.png`

**Interfaces:**
- Produces: `ImageDecoding.inspect(url:)`, `decode(_:)`, `DecodeCancellation`, and byte-costed `RasterCache`.
- Consumes: `DecodeRequest`, `RasterAsset`, and `ImageLoadError` from Task 2.

- [ ] **Step 1: Write failing decoder and eviction tests**

Assert EXIF orientation 6 produces upright dimensions, a target of 800 pixels does not decode a 4000-pixel long edge, alpha remains present, overflow dimensions fail before allocation, and inserting costs 60 then 60 into a budget of 100 evicts the least recently used entry.

- [ ] **Step 2: Run the two test classes**

Expected: FAIL because decoder and cache are undefined.

- [ ] **Step 3: Implement metadata-first ImageIO decoding**

Create sources with `kCGImageSourceShouldCache: false`; read properties first; use `CGImageSourceCreateThumbnailAtIndex` with transform and max-pixel-size options for preview requests; use checked multiplication for decoded cost; check cancellation before and after Core Graphics calls.

- [ ] **Step 4: Implement an LRU cache measured in decoded bytes**

Use a serial lock-protected structure keyed by source identity plus target size. `removeAllNonessential()` keeps only explicitly pinned current assets. Register memory-pressure handling in the application layer, not inside tests.

- [ ] **Step 5: Run decoder, cache, and complete tests**

Expected: PASS; Instruments leaks are not part of this step.

- [ ] **Step 6: Commit**

```bash
git add Sources/Imaging Tests/Unit Tests/Fixtures/Static
git commit -m "feat: decode and cache static images"
```

### Task 7: Load pipeline and viewing session

**Files:**
- Create: `Sources/Imaging/ImageLoadPipeline.swift`
- Create: `Sources/Viewer/ViewingSession.swift`
- Create: `Tests/Unit/ImageLoadPipelineTests.swift`
- Create: `Tests/Unit/ViewingSessionTests.swift`

**Interfaces:**
- Produces: `ImageLoadPipeline.load(_:completion:) -> DecodeCancellation`, `ViewingSession.open(_:)`, navigation commands, and observable `ViewingState` changes.
- Consumes: access providers, catalog, decoder, cache, and `DisplayAsset`.

- [ ] **Step 1: Write stale-result and navigation tests with controlled decoders**

Start load A, start load B, complete B, then complete A. Assert B remains current. Assert navigating from the last item does not wrap when disabled and reaches the first item when enabled.

- [ ] **Step 2: Run pipeline/session tests**

Expected: FAIL because pipeline and session are undefined.

- [ ] **Step 3: Implement operation-queue loading and generation checks**

Use a decode `OperationQueue` with user-initiated quality of service. Deliver state changes on the main queue. Each open increments `UInt64 generation`; only matching completions publish. Navigation cancels the prior token before submitting the next request.

- [ ] **Step 4: Add bounded neighbor preview scheduling**

Preload only the configured neighbors at viewport preview resolution and utility quality of service. A foreground load may reuse a matching cached preview while scheduling a sharper raster when needed.

- [ ] **Step 5: Run all unit tests repeatedly**

Run the full suite three times to expose ordering races. Expected: all runs PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Imaging/ImageLoadPipeline.swift Sources/Viewer Tests/Unit
git commit -m "feat: coordinate cancellable viewing sessions"
```

### Task 8: Native canvas, commands, and welcome UI

**Files:**
- Create: `Sources/Canvas/ImageCanvasView.swift`
- Modify: `Sources/Viewer/ViewerWindowController.swift`
- Create: `Sources/Preferences/CommandCatalog.swift`
- Create: `Sources/Preferences/PreferencesStore.swift`
- Create: `Sources/Interface/WelcomeViewController.swift`
- Modify: `Sources/Application/AppCoordinator.swift`
- Create: `Tests/Unit/CommandCatalogTests.swift`
- Create: `Tests/Unit/PreferencesStoreTests.swift`
- Create: `Tests/UI/ViewerSmokeTests.swift`

**Interfaces:**
- Produces: first working viewer UI and fixed responder-chain actions.
- Consumes: `ViewingSession`, `ViewportGeometry`, and `DisplayAsset`.

- [ ] **Step 1: Write command and preference tests**

Assert command identifiers are unique, the documented shortcut table matches `CommandCatalog`, invalid zoom steps restore the default, and preload raw values decode only to Off/One/Two.

- [ ] **Step 2: Run tests and verify failure**

Expected: FAIL because catalog and preferences are undefined.

- [ ] **Step 3: Implement command catalog and typed preferences**

Create immutable definitions for Open, New Window, Close, navigation, zoom modes, rotation, flips, full screen, playback, slideshow, information, Reveal in Finder, and MP4 export. Construct `NSMenuItem` instances from these definitions and use the same definitions in the welcome keyboard map.

- [ ] **Step 4: Implement the layer-backed canvas and window controller**

Draw the current `CGImage` in `draw(_:)` or a backing layer using geometry results. Convert scroll, magnify, mouse drag, double-click, and key/responder actions into session or viewport intents. Set interpolation quality from zoom state. Do not decode in the view.

- [ ] **Step 5: Implement the welcome view in AppKit**

Use `NSVisualEffectView`, `NSStackView`, and a small collection/grid of key caps. Include Open and drag/drop actions, principal shortcuts, gestures, accessibility labels, and Help-menu reopening. No HTML resource is added.

- [ ] **Step 6: Write and run a UI smoke test**

Launch with `-ApplePersistenceIgnoreState YES -LightViewUITestEmptyWindow YES`; assert the welcome view and Open button exist. Drag/open the static fixture through a launch argument and assert the canvas and filename title appear.

- [ ] **Step 7: Run the complete foundation gate**

Run all unit/UI tests, build x86_64 Debug, and build arm64 Debug. Open a small JPEG manually and verify navigation, zoom, pan, rotate, flip, full screen, multiple windows, and the Help guide.

- [ ] **Step 8: Commit**

```bash
git add Sources Tests Resources LightView.xcodeproj Config
git commit -m "feat: deliver native static image viewer"
```

### Task 9: Appearance, information, and macOS integration

**Files:**
- Create: `Sources/Interface/PreferencesWindowController.swift`
- Create: `Sources/Interface/ImageInfoWindowController.swift`
- Create: `Sources/Application/SystemIntegration.swift`
- Modify: `Sources/Application/AppCoordinator.swift`
- Modify: `Sources/Canvas/ImageCanvasView.swift`
- Modify: `Sources/Viewer/ViewerWindowController.swift`
- Create: `Tests/Unit/SystemIntegrationTests.swift`
- Create: `Tests/UI/PreferencesAndInfoSmokeTests.swift`

**Interfaces:**
- Produces: appearance/background preferences, system recent documents, Reveal in Finder, Open With, Reload, and the image-information window.
- Consumes: `PreferencesStore`, current catalog entry, and `ImageMetadata`.

- [ ] **Step 1: Write system-integration and presentation-model tests**

Assert Reveal in Finder requests selection of the exact standardized URL, Open With receives only the current local file, Reload retains the current viewport mode while replacing the asset, information rows contain name/path/bytes/pixel size/format/frame count/color profile/dates, and custom background values round-trip without accepting unreadable files.

- [ ] **Step 2: Run the new unit tests**

Expected: FAIL because `SystemIntegration` and information presentation types are undefined.

- [ ] **Step 3: Implement macOS services behind injectable wrappers**

Use `NSDocumentController.noteNewRecentDocumentURL`, `NSWorkspace.activateFileViewerSelecting`, and an `NSWorkspace` application-selection/open operation. Keep wrapper protocols in tests so no Finder or third-party app is launched by unit tests. Reload submits a new generation for the same URL.

- [ ] **Step 4: Implement native preferences and information windows**

Build AppKit controls for Follow System/Light/Dark, black/dark gray/white/custom color, optional local background image, sorting, wrapping, preload, initial zoom, zoom step, auto-resize, slideshow, animation energy saving, and welcome visibility. Import a background through `NSOpenPanel`, decode a bounded display-sized copy, and store that application-owned copy under Application Support so neither distribution needs persistent access to the original. Build a selectable-text information grid from immutable metadata. Neither window uses SwiftUI.

- [ ] **Step 5: Handle display changes**

Observe window backing-property changes, update canvas contents scale and color space, invalidate only scale/color-dependent rasters, and retain the same image-space center. Add a test that changes backing scale from 1 to 2 and verifies requested raster dimensions double without changing the logical viewport.

- [ ] **Step 6: Run the complete Plan 1 gate**

Run all unit and UI tests; build x86_64 and arm64; manually verify Open Recent, Reveal in Finder, Open With, Reload, information, preferences, custom background, light/dark appearance, and a window moved between displays.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: complete native macOS viewer integration"
```
