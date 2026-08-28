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
