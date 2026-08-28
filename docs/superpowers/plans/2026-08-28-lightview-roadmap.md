# LightView Delivery Roadmap

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this roadmap task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver LightView as a tested Universal 2 AppKit image viewer in Direct and Mac App Store configurations, including native animation and MP4 export.

**Architecture:** Work is divided into four reviewable plans. Each plan leaves the repository in a working state and is a prerequisite for the next. Product behavior is defined by `docs/requirements.md`; component contracts and quality constraints are defined by `docs/technical-spec.md`.

**Tech Stack:** Swift 6 language toolchain with macOS 10.15-compatible APIs, AppKit, ImageIO, Core Graphics, Core Animation, AVFoundation, XCTest, NanoSVG, libwebp, shell benchmark utilities.

**Spec:** `docs/requirements.md` and `docs/technical-spec.md`

## Global Constraints

- Use AppKit; do not import SwiftUI or WebKit.
- Build x86_64 for macOS 10.15+ and arm64 for macOS 11.0+.
- Produce Universal 2 Direct and App Store artifacts from one source tree.
- Do not copy qView, Tovi, or SimpView source, architecture, or naming.
- Do not implement network URL opening, file mutation, shortcut customization, or thumbnail/catalog UI.
- Keep decoder and cache allocations bounded and cancellable.
- Follow red-green-refactor TDD for every behavior-bearing task.

---

## Plans

- [ ] **Plan 1 — Native viewer foundation:** `2026-08-28-lightview-foundation.md`
  - Project, tests, file catalog, access abstraction, static ImageIO decoding, viewport math, cache, AppKit window, welcome guide, fixed commands.
- [ ] **Plan 2 — Formats and playback:** `2026-08-28-lightview-formats-playback.md`
  - NanoSVG, libwebp, animated GIF/APNG/WebP, playback clock, slideshow, format UI.
- [ ] **Plan 3 — Export and distribution:** `2026-08-28-lightview-export-distribution.md`
  - MP4 timeline/compositor/writer, export UI, sandbox bookmarks, dual release configurations, localization.
- [ ] **Plan 4 — Verification and documentation:** `2026-08-28-lightview-verification-docs.md`
  - Malformed fixtures, UI smoke tests, performance harness, four-app comparison, compatibility evidence, README and release checklist.

## Execution gates

1. Do not start Plan 2 until Plan 1 tests and a static-image UI smoke test pass.
2. Do not start Plan 3 until static SVG/WebP and all animation timing tests pass.
3. Do not start Plan 4 until MP4 export and both file-access configurations pass integration tests.
4. Do not claim completion until Plan 4 records fresh Release evidence.

