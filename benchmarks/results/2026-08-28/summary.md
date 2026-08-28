# Four-viewer 12000×8000 JPEG comparison

Measured on an Apple M1 MacBook Pro (16 GB) running macOS 26.6.2 (25G83). The input is a 2,153,248-byte 12000×8000 JPEG with SHA-256 `b2c5dcf52af71b129c9f8d2f5bda92c5e08d343596bb04b068e96c35884af995`.

## Applications

| Application | Version/source identity | Architectures | Signing used for this run |
|---|---|---|---|
| LightView | 0.1.0, `codex/lightview-development` | x86_64 + arm64 | ad hoc Release-Direct |
| qView | 7.1; local source checkout `0ec246b78c310d5c842836a91566db24037c75c2` | x86_64 + arm64 | ad hoc |
| Tovi | installed 2.0.4 (210), distinct from public Tovi 1.5 source | x86_64 (Rosetta) | ad hoc |
| SimpView | installed `2026-07-31.d8a824f` | arm64 | Developer ID |

## Size

| Application | `.app` logical | `.app` allocated | Main Mach-O |
|---|---:|---:|---:|
| LightView | 4.19 MiB | 4.20 MiB | 3.11 MiB |
| qView | 116.41 MiB | 116.59 MiB | 3.19 MiB |
| Tovi 2.0.4 | 5.11 MiB | 5.25 MiB | 0.87 MiB |
| SimpView | 1.91 MiB | 1.92 MiB | 1.10 MiB |

LightView's universal main binary includes both supported CPU architectures and statically linked NanoSVG/libwebp code. qView's bundle size is dominated by Qt frameworks and plug-ins rather than its similarly sized main executable.

## Settled RSS

Each application was closed before measurement. Three alternating-order LaunchServices runs opened the same image; after five seconds, the harness collected five samples at 0.5-second intervals. Values below are the 15-sample main-process RSS. Descendant-process RSS was zero for all four applications in these runs.

| Application | Median RSS | Mean RSS | Observed range | Median vs LightView |
|---|---:|---:|---:|---:|
| LightView | 149.20 MiB | 134.96 MiB | 118.41–149.45 MiB | 1.00× |
| Tovi 2.0.4 | 408.62 MiB | 283.37 MiB | 32.70–408.84 MiB | 2.74× |
| qView | 519.72 MiB | 658.89 MiB | 474.11–982.83 MiB | 3.48× |
| SimpView | 795.83 MiB | 701.72 MiB | 489.88–819.50 MiB | 5.33× |

Tovi varied sharply: two runs settled near 409 MiB and one near 33 MiB, so the median is more representative than its mean. The global RSS of existing `com.apple.WebKit.*` processes was sampled before and after every run. Tovi's three deltas were all 0 KiB; therefore no helper increment was added in this dataset. This does not prove that WebKit costs nothing: legacy WebView work may be in-process, shared processes may already exist, and RSS double-counts shared pages.

The first corpus under `raw-superseded-direct-argv/` is intentionally retained but excluded. Passing the image as a raw executable argument did not reliably deliver an open-document event to SimpView. The accepted `raw/` corpus uses LaunchServices for all reference viewers and LightView's deterministic UI-test open argument.

## Evidence

- Environment and fixture identity: `environment.json`
- Accepted measurements: `raw/round-1.tsv`, `raw/round-2.tsv`, `raw/round-3.tsv`
- Exact bundle/Mach-O values: `raw/sizes.tsv`
- Per-run WebKit baselines: `raw/*-webkit.tsv`
- Superseded method retained for audit: `raw-superseded-direct-argv/`
