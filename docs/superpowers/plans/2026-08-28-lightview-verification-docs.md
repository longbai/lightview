# LightView Verification and Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove LightView's correctness, compatibility, resource use, and distribution properties, then publish reproducible documentation and the four-application comparison.

**Architecture:** Verification scripts treat built applications as black boxes where possible. Unit/integration tests retain deterministic fixtures; performance tests record raw samples and environment metadata before producing summaries.

**Tech Stack:** XCTest, xcodebuild, shell, `/usr/bin/time`, `ps`, `vmmap`, `footprint`, `lipo`, `otool`, `codesign`, `spctl`, AVFoundation inspection.

**Spec:** `docs/requirements.md`, `docs/technical-spec.md`, and `benchmark-results.md`

## Global Constraints

- Compare Release builds with the same files, launch order, settle time, and foreground state.
- Record main-process and attributable helper-process memory; state RSS limitations.
- Never claim Intel Catalina compatibility from compilation alone.
- README figures must come from committed raw result files, not manual transcription.
- Completion requires Direct and App Store configuration evidence.

---

### Task 1: Malformed and resource-limit test corpus

**Files:**
- Create: `Tests/Fixtures/Malformed/`
- Create: `Tests/Integration/MalformedInputTests.swift`
- Create: `Tests/Integration/AllocationLimitTests.swift`
- Create: `scripts/generate-test-fixtures.swift`

**Interfaces:**
- Produces: deterministic redistributable corrupt/truncated/oversized fixtures and crash-free assertions for every decoder route.

- [ ] **Step 1: Write failing malformed-input tests**

Cover truncated JPEG/PNG/GIF/WebP, false extensions, zero dimensions, overflow dimensions, excessive animation frame declarations, SVG entity/external-resource cases, and AVIF on unsupported systems. Each test expects a specific `ImageLoadError` category and no published stale asset.

- [ ] **Step 2: Run the tests with Address Sanitizer**

Expected: any missing validation fails without treating a process crash as success.

- [ ] **Step 3: Add validation at the owning decoder boundary**

Keep each check next to the allocation or parser it protects. Set exact source-size, dimension, decoded-byte, frame-count, and duration ceilings in a typed `DecodeSafetyLimits` value covered by tests.

- [ ] **Step 4: Re-run sanitizer and normal suites, then commit**

```bash
git add Tests scripts Sources/Imaging
git commit -m "test: harden malformed image handling"
```

### Task 2: End-to-end UI and distribution smoke suite

**Files:**
- Create: `Tests/UI/EndToEndViewerTests.swift`
- Create: `Tests/UI/AccessibilityTests.swift`
- Create: `scripts/smoke-release.sh`

**Interfaces:**
- Produces: automated evidence for launch, open, navigation, transforms, animation, slideshow, export, multiple windows, localization, and sandbox authorization UI.

- [ ] **Step 1: Add end-to-end UI tests with fixture launch arguments**

Assert the visible title/current position after navigation; exercise fixed shortcuts; verify full-screen entry/exit, separate window state, welcome Help reopening, animation pause, slideshow stop, and a completed short MP4 export.

- [ ] **Step 2: Add accessibility assertions**

Assert every actionable welcome, preference, information, and export control has a nonempty label and is keyboard reachable. Run once under English and once under zh-Hans.

- [ ] **Step 3: Run Direct and App Store smoke scripts**

The script launches a fresh preference domain, opens fixtures, records failures, checks entitlements, and leaves generated artifacts under `build/smoke-results/`.

- [ ] **Step 4: Fix only evidence-backed failures and rerun the complete suite**

Expected: both configurations PASS with zero unexpected console crashes.

- [ ] **Step 5: Commit**

```bash
git add Tests/UI scripts/smoke-release.sh
git commit -m "test: add end-to-end release smoke coverage"
```

### Task 3: Reproducible performance harness

**Files:**
- Create: `scripts/benchmark-app.sh`
- Create: `scripts/benchmark-suite.sh`
- Create: `benchmarks/README.md`
- Create: `benchmarks/fixtures/manifest.txt`
- Create: `Tests/Performance/GeometryPerformanceTests.swift`
- Create: `Tests/Performance/DecodePerformanceTests.swift`

**Interfaces:**
- Produces: timestamped raw TSV/JSON samples and Markdown summary inputs for bundle bytes, Mach-O bytes, launch time, first frame, RSS, peak RSS, child processes, traversal, animation, SVG, and export.

- [ ] **Step 1: Write a harness self-test against a controlled helper process**

Verify PID discovery, five-sample median calculation, peak capture, timeout, process cleanup, and raw environment fields. Reject a run when another process with the target bundle identifier was already active.

- [ ] **Step 2: Implement black-box application measurement**

Accept explicit app path and fixture path; launch via executable with test-only arguments; wait for a readiness marker; sample `ps` and `footprint`; record child process deltas; terminate only the PID launched by the harness.

- [ ] **Step 3: Add fixed benchmark scenarios**

Include empty, small JPEG, 12000x8000 fit, the same image actual-size, 100-file traversal, animated GIF/WebP, path-heavy SVG, and 1080p MP4 export. Run at least three alternating runs and five settled memory samples per run.

- [ ] **Step 4: Run LightView budgets and commit harness code**

Expected: the script exits nonzero for any unmet requirement budget and retains raw results.

```bash
git add scripts benchmarks Tests/Performance
git commit -m "perf: add reproducible LightView benchmarks"
```

### Task 4: Four-application comparison

**Files:**
- Create: `benchmarks/results/2026-08-28/environment.json`
- Create: `benchmarks/results/2026-08-28/raw/`
- Create: `benchmarks/results/2026-08-28/summary.md`
- Modify: `benchmark-results.md`

**Interfaces:**
- Produces: fresh LightView/qView/Tovi/SimpView comparison with traceable raw samples.

- [ ] **Step 1: Build or identify signed-equivalent Release artifacts**

Record source commit, architecture, deployment target, signing mode, and exact app path for every application. Do not mix installed Tovi 2.0.4 results with open-source Tovi 1.5 without labeling them separately.

- [ ] **Step 2: Run alternating benchmark rounds**

Close all four apps, establish helper-process baselines, then run the same ordered suite. Include WebKit helper delta for Tovi and verify qView helper processes rather than comparing main PID alone.

- [ ] **Step 3: Generate the summary from raw data**

Report medians, means where useful, peaks, ratios, app logical/allocated size, Mach-O size, and limitations. Keep prior baseline text and mark superseded methods rather than deleting historical evidence.

- [ ] **Step 4: Review arithmetic and commit results**

```bash
git add benchmarks/results benchmark-results.md
git commit -m "perf: compare LightView with reference viewers"
```

### Task 5: Compatibility and release evidence

**Files:**
- Create: `docs/compatibility-matrix.md`
- Create: `docs/release-checklist.md`
- Create: `scripts/verify-compatibility.sh`

**Interfaces:**
- Produces: release evidence for Intel Catalina, current Intel, Apple silicon Big Sur, current Apple silicon, architecture slices, entitlements, signing, and notarization/App Store readiness.

- [ ] **Step 1: Automate binary compatibility inspection**

Inspect architectures, load-command minimum OS values, linked frameworks, forbidden frameworks, code signature, Hardened Runtime, sandbox entitlements, and bundled third-party licenses. Fail on a missing or unexpected property.

- [ ] **Step 2: Execute real-system launch tests**

On Intel macOS 10.15, open static ImageIO, SVG, WebP, GIF, folder navigation, and 480p export. On Apple silicon macOS 11, repeat and confirm native arm64 execution. Record hardware, OS build, result, and tester date.

- [ ] **Step 3: Validate current-system Direct and App Store workflows**

Run Gatekeeper assessment and notarization stapling checks for Direct. Validate provisioning/entitlements and folder bookmark behavior for App Store. Record commands and outputs with secrets removed.

- [ ] **Step 4: Commit evidence**

```bash
git add docs/compatibility-matrix.md docs/release-checklist.md scripts/verify-compatibility.sh
git commit -m "docs: record compatibility and release evidence"
```

### Task 6: Final README and completion verification

**Files:**
- Create: `README.md`
- Create: `THIRD_PARTY_NOTICES.md`
- Modify: `docs/requirements.md`
- Modify: `docs/technical-spec.md`

**Interfaces:**
- Produces: final user/developer documentation tied to verified artifacts and results.

- [ ] **Step 1: Write README content from committed evidence**

Include purpose, screenshots, supported OS/architectures, formats and AVIF limitation, fixed shortcut table, gestures, Direct/App Store folder behavior, MP4 export, privacy, build/test commands, performance method/table, and links to raw results.

- [ ] **Step 2: Add exact third-party notices**

List NanoSVG repository/commit/zlib license and libwebp repository/tag/commit/BSD license. Include full required license texts without claiming ownership.

- [ ] **Step 3: Reconcile requirements/spec status**

Mark implemented requirements with their verification artifact. Document any explicitly accepted deviation with rationale and user approval; do not silently lower a performance or compatibility requirement.

- [ ] **Step 4: Run final verification**

Run all unit, integration, UI, sanitizer, performance-budget, artifact, compatibility, and documentation-link checks from a clean build. Capture command exit codes and artifact hashes.

- [ ] **Step 5: Request code review and address findings**

Use `superpowers:requesting-code-review`; review requirements coverage, safety boundaries, concurrency, memory, entitlements, licensing, and reproducibility. Apply accepted findings with their own tests and commits.

- [ ] **Step 6: Commit final documentation**

```bash
git add README.md THIRD_PARTY_NOTICES.md docs
git commit -m "docs: complete LightView release documentation"
```

