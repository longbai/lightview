# LightView Product Requirements

Status: Draft for review  
Date: 2026-08-28

## 1. Product definition

LightView is a lightweight, native image viewer for macOS. It combines the useful viewing, navigation, animation, slideshow, and video-export capabilities observed in qView and Tovi while using a new Swift/AppKit codebase with its own architecture and naming.

The product prioritizes:

1. Fast launch and low memory use.
2. A distraction-free image-first interface.
3. Predictable keyboard, mouse, and trackpad operation.
4. Native behavior on both Intel and Apple silicon Macs.
5. A common codebase for direct distribution and the Mac App Store.

SimpView is used only as a performance comparison baseline. Its source architecture and naming are not design inputs for LightView.

## 2. Supported platforms and distributions

### 2.1 Operating systems

- Intel (`x86_64`): macOS 10.15 Catalina or later.
- Apple silicon (`arm64`): macOS 11 Big Sur or later.
- The release application is a Universal 2 bundle.
- SwiftUI is not used. The interface is implemented with AppKit.

### 2.2 Distribution configurations

LightView is built from one source tree with two release configurations:

- `Release-Direct`: Developer ID signed, notarized, Hardened Runtime enabled, App Sandbox disabled.
- `Release-AppStore`: Mac App Store signed, App Sandbox enabled, user-selected file access and security-scoped bookmarks enabled.

The configurations provide the same viewing and export features. They are alternative distribution channels and are not intended to be installed side by side.

## 3. Functional requirements

### 3.1 Opening local content

LightView shall:

- Open supported images from Finder, the Dock, the File menu, Open Recent, and drag and drop.
- Accept either individual image files or folders.
- Scan the containing folder non-recursively and create an ordered list of supported images.
- Refresh the list when the current file disappears or when the user explicitly reloads it.
- Open multiple independent viewer windows.
- Restore the most recently used window size and appearance settings.
- Display an actionable error for unreadable, damaged, unsupported, or inaccessible files.

The App Store build shall display the selected image immediately. If its parent folder is not authorized, it shall request folder access only when adjacent-file navigation is requested. A successful folder selection shall be stored as a read-only security-scoped bookmark.

### 3.2 Image navigation

LightView shall provide:

- Previous, next, first, and last image navigation.
- Natural filename sorting.
- Sort by filename, modification date, creation date, and file size.
- Ascending and descending order.
- Optional wrapping at the start and end of a folder.
- Configurable adjacent-image preloading as Off, One Neighbor, or Two Neighbors.
- Clear current-position feedback such as `12 / 240` without permanently occupying image space.

Folder traversal is non-recursive in version 1. A thumbnail browser and folder tree are out of scope.

### 3.3 Viewing and transforms

LightView shall provide:

- Fit to window.
- Fill window.
- Actual size at one image pixel per display point, adjusted correctly for Retina backing scale.
- Zoom in and zoom out.
- Zoom centered on the pointer or gesture location.
- Click-and-drag panning when the image exceeds the viewport.
- Smooth trackpad pinch and scroll handling.
- Rotate left and rotate right in 90-degree increments.
- Horizontal and vertical flip.
- Full-screen viewing.
- Optional automatic viewer-window resizing constrained to the visible screen.
- Pixel-sharp rendering at integral high zoom levels and high-quality filtering when reducing images.

Rotation and flipping are session-only presentation transforms. LightView shall not modify or overwrite source files.

### 3.4 Animated images

LightView shall:

- Play animated GIF, APNG, and animated WebP.
- Preserve frame order, frame duration, disposal method, alpha, and loop count where the format provides them.
- Support play, pause, next frame, slower, normal speed, and faster playback.
- Pause animation when a window is no longer visible if the user enables the energy-saving preference.
- Decode frames on demand within a bounded cache instead of retaining every full-size frame unconditionally.

### 3.5 Slideshow

LightView shall provide:

- Start, pause, resume, and stop.
- Forward or reverse playback.
- Configurable interval.
- Optional folder wrapping.
- Full-screen operation.
- Immediate cancellation when the user manually navigates, according to preference.

### 3.6 MP4 export

LightView shall export the current image or the current folder sequence as a silent MP4 slideshow using AVFoundation.

The export panel shall provide:

- 480p, 720p, and 1080p output presets.
- Preservation of source aspect ratio.
- Fit or fill composition.
- Solid-color or user-selected image background.
- Slide and fade transitions.
- Configurable duration for static images.
- GIF/animated-image duration options: one loop, source loop count when finite, or a user-defined maximum duration.
- Progress, cancellation, and a clear success or failure result.
- Output destination through `NSSavePanel`.

The output format is H.264 video in an `.mp4` container for broad compatibility. Audio tracks, captions, timeline editing, arbitrary effects, and general-purpose video editing are out of scope.

### 3.7 File information and system integration

LightView shall provide:

- Reveal in Finder.
- Open With using macOS application selection.
- Reload file.
- File information showing name, path, byte size, pixel dimensions, format, frame count, color profile when available, creation date, and modification date.
- Standard macOS application, File, View, Window, and Help menus.
- System Recent Documents integration.

LightView shall not provide copying, pasting, renaming, deleting, moving to Trash, permanent deletion, or undoing file operations.

### 3.8 Welcome and help interface

On first launch with no image, LightView shall show a native image-oriented welcome view inspired by Tovi's concise shortcut introduction without copying Tovi assets or implementation.

It shall include:

- An Open Image or Folder action.
- A drag-and-drop target.
- A visual keyboard map for the principal fixed shortcuts.
- A concise mouse and trackpad gesture guide.
- A way to reopen the guide from the Help menu.
- A preference controlling whether the guide appears when a new empty window opens.

The welcome interface shall use AppKit visual-effect, stack, collection, and text views. It shall not load HTML or start WebKit processes.

### 3.9 Appearance

LightView shall support:

- Follow System, Light, and Dark appearance choices.
- Black, dark gray, white, and custom solid viewer backgrounds.
- An optional user-selected background image.
- High-resolution Retina rendering.
- Multiple displays and changes in backing scale or color space.

LightView shall not bundle Tovi's picture-theme assets.

### 3.10 Preferences and shortcuts

Preferences shall include appearance, background, sort order, wrapping, preload level, slideshow interval/direction, animation energy saving, initial zoom mode, zoom step, window resizing behavior, and welcome-guide visibility.

Keyboard shortcuts are fixed and displayed in menus and the welcome guide. Shortcut customization is out of scope.

Initial shortcut map:

| Action | Shortcut |
|---|---|
| Open | Command-O |
| New window | Command-N |
| Close window | Command-W or Escape outside full screen |
| Previous / Next | Left / Right Arrow |
| First / Last | Command-Left / Command-Right |
| Zoom in / out | Plus / Minus or Up / Down Arrow |
| Fit to window | F |
| Fill window | Shift-F |
| Actual size | 1 |
| Rotate left / right | Shift-Left / Shift-Right |
| Horizontal / vertical flip | H / V |
| Full screen | Control-Command-F |
| Play or pause animation | Space |
| Start or stop slideshow | Return |
| File information | Command-I |
| Reveal in Finder | Command-R |
| Export MP4 | Command-E |

Shortcuts that conflict with text entry or system behavior shall be inactive while an editable control has focus.

## 4. Image format requirements

### 4.1 Native ImageIO path

LightView shall use ImageIO for formats available on the running system, including common JPEG, PNG, GIF, TIFF, BMP, ICO, JPEG 2000, HEIF/HEIC, and supported camera RAW formats.

ImageIO capability shall be detected at runtime. A filename extension alone shall not be treated as proof of format.

### 4.2 SVG

- Static SVG is parsed with a vendored NanoSVG-derived parser and rendered with Core Graphics.
- Supported content includes basic geometry, paths, fills, strokes, opacity, transforms, viewBox, and supported gradients.
- Scripts, external URLs, external files, `foreignObject`, animation, and complex filter chains are never executed.
- Unsupported SVG features produce a partial-support notice or an explicit error.

### 4.3 WebP

- ImageIO is attempted first on systems that support WebP.
- A statically linked, decoder-only build of Google's `libwebp` is used when ImageIO is unavailable or fails.
- Static and animated WebP are supported on every LightView-supported system.
- Encoding tools, command-line utilities, examples, and tests are not shipped in the application.

### 4.4 AVIF

- AVIF uses ImageIO on macOS 13 or later when the operating system accepts the file.
- macOS 10.15 through 12 display a clear unsupported-system message for AVIF.
- LightView version 1 does not bundle `libavif`, dav1d, libaom, or another AV1 decoder.

## 5. Non-functional requirements

### 5.1 Performance

All measurements shall use signed-equivalent Release builds with debug diagnostics disabled.

Targets on the reference Apple silicon development Mac:

- Empty-window median RSS after settling: no more than 55 MiB.
- Small JPEG median RSS after settling: no more than 80 MiB.
- A 12000 x 8000 JPEG initially fit to the window: no more than 225 MiB median RSS and no more than 300 MiB peak RSS during initial presentation.
- No WebKit, Electron, Qt, browser, or persistent decoder helper process.
- Cold launch to responsive empty window: target below 300 ms on the reference machine.
- Small local image open to first visible frame: target below 150 ms after application launch.
- Adjacent navigation with a completed preload: target below 50 ms to first visible frame.
- Universal 2 Direct `.app` logical size: target below 10 MiB before code-signature variance.
- Universal 2 main Mach-O size: target below 7 MiB.

Performance targets are budgets, not permission to reduce correctness. Results shall be reported alongside hardware, OS version, test image, run count, median, and peak values.

### 5.2 Memory behavior

- Metadata is read before raster allocation.
- Initial decode size is based on viewport size and backing scale.
- Full-resolution decode is deferred until the requested zoom requires it.
- Decode jobs are cancellable when the user navigates away.
- Cache accounting uses decoded bytes, not compressed file size.
- Cached images are evicted under memory pressure and when windows close.
- Animation and export use bounded frame pipelines.
- The application shall release the current full-resolution raster after switching files unless it remains inside the configured cache budget.

### 5.3 Responsiveness and concurrency

- Filesystem enumeration, metadata inspection, decoding, SVG parsing, WebP decoding, and MP4 composition shall not block the main thread.
- AppKit view and menu updates remain on the main thread.
- A stale asynchronous result shall never replace a newer navigation result.
- Closing a window cancels work owned only by that window.

### 5.4 Accessibility and localization

- Interactive controls shall have accessibility labels, roles, keyboard reachability, and sufficient contrast.
- Reduce Motion shall suppress nonessential welcome and transition animation.
- Version 1 shall include English and Simplified Chinese interface resources.
- File names and paths shall support arbitrary Unicode.

### 5.5 Privacy and security

- No telemetry, analytics, advertising, account system, or image upload.
- No network-image or URL opening.
- No in-app network updater in version 1.
- SVG external resources and scripts are disabled.
- Malformed images must fail without crashing or unbounded allocation.
- Direct distribution uses Hardened Runtime, signing, and notarization.
- The App Store build requests only file capabilities necessary for viewing and exporting.

## 6. Explicitly out of scope

- Image editing or saving presentation transforms into source files.
- Copy/paste image operations.
- Rename, delete, Trash, permanent delete, or undo file operations.
- Custom keyboard shortcut editing.
- Network URLs or remote image download.
- Thumbnail grid, folder tree, catalog/database, tags, ratings, or search.
- Recursive folder browsing.
- Metadata editing.
- Printing.
- General-purpose video editing or audio export.
- SwiftUI, WebKit, Qt, Electron, and browser-based rendering.
- Side-by-side installation of Direct and App Store editions.

## 7. Release acceptance

A version 1 release is acceptable only when:

1. Both release configurations build successfully as Universal 2 applications.
2. The x86_64 slice declares macOS 10.15 and the arm64 slice declares macOS 11.0.
3. Unit, integration, UI smoke, malformed-input, and export tests pass.
4. Direct and sandbox file-access workflows pass their separate acceptance tests.
5. Supported static and animated format fixtures render correctly.
6. Performance results are recorded against Tovi, qView, and the existing SimpView baseline using the same input files and measurement method.
7. The README documents features, shortcuts, compatibility, privacy, build instructions, third-party licenses, and measured performance.
8. The Direct build passes signing, Hardened Runtime, and notarization validation; the App Store build passes entitlement validation.

