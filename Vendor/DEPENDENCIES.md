# Vendored Dependencies

LightView keeps third-party decoder sources pinned and auditable. Upstream code is
kept in Git submodules; LightView-specific ownership and safety boundaries live in
adjacent adapter files and are not patched into the upstream checkout.

## NanoSVG

- Repository: `https://github.com/memononen/nanosvg.git`
- Pinned commit: `239e102ec2c691f2902e20ace2ed36ee4a35cfe6`
- Parser source: `Vendor/NanoSVG/upstream/src/nanosvg.h`
- Parser SHA-256: `e34fd5d084be106cea972d19ce5d27fd96d17ba89f8d06bdceee058420c8b2b0`
- License: zlib license, reproduced in `Vendor/NanoSVG/upstream/LICENSE.txt`
- Integration: LightView imports only `LightViewSVGAdapter.h`; NanoSVG structs are
  private to the C adapter implementation.

The adapter is built with scripting and external-resource loading absent by design.
LightView additionally scans SVG source before parsing and rejects external references.

## libwebp

- Repository: `https://chromium.googlesource.com/webm/libwebp`
- Release: `v1.6.0`
- Pinned commit: `4fa21912338357f89e4fd51cf2368325b59e9bd9`
- Public decoder header SHA-256: `e554551d085f234e930f36b5879a77ef58bfea34c48ebfd620426e63b224025c`
- Public demux header SHA-256: `9b0d10c0fa1ac2dc750c4d687b038e40a685bb9240cb045759f5b9546017361d`
- License: BSD 3-Clause, reproduced in `Vendor/libwebp/upstream/COPYING`
- Build script: `scripts/build-libwebp.sh`

The `LightViewCore` target has a dependency-aware **Prepare libwebp** build phase.
After submodules are initialized, an ordinary Xcode or `xcodebuild` build creates
missing architecture archives automatically; developers may also run the build
script directly. CMake and the Xcode command-line tools are required.

The script configures separate MinSizeRel builds for x86_64/macOS 10.15 and
arm64/macOS 11.0. Shared libraries and every command-line, encoder-facing,
muxing, JavaScript, extra, and fuzz target are disabled; SIMD remains enabled.
Only `libwebpdecoder.a` and `libwebpdemux.a` are linked into LightView. Upstream's
`webpdemux` CMake dependency transiently builds `libwebp.a`, but that encoder
archive is neither copied nor linked.

Archive SHA-256 values from the pinned clean build:

| Architecture | Archive | SHA-256 |
| --- | --- | --- |
| x86_64 | `libwebpdecoder.a` | `c4b975301ea33c45fd80da6a27ee5d17c889ed6552f5aa285c2043e67eef2960` |
| x86_64 | `libwebpdemux.a` | `9a6c1bdfcaa4f83b52b899cd55792d02eeab99e16d2b496bf04f5505256754e7` |
| arm64 | `libwebpdecoder.a` | `259afb549727e3faec590ccc81acc17f49d8e040b652c176bba183feaaf5dccc` |
| arm64 | `libwebpdemux.a` | `0e4969c95f9af6c1c85dbdcb4e0811a94b456a2796d44f26e97c2011aa90ca4a` |

The demux archive contains only `anim_decode.c.o` and `demux.c.o`. The decoder
archive contains decoder (`src/dec`), decoder DSP (`src/dsp`), and decoder utility
(`src/utils`) objects; `ar -t` contains no `src/enc` object. Architecture-specific
SIMD objects are compiled by upstream feature guards and dead-stripped when unused.
