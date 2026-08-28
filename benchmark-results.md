# Image Viewer Release Benchmarks

## Current four-application comparison

The reproducible 2026-08-28 comparison now covers LightView 0.1.0, qView 7.1, installed Tovi 2.0.4, and SimpView. All four opened the same 12000×8000 JPEG in three alternating cold-start rounds, with five settled RSS samples per round.

| Application | `.app` logical | Main Mach-O | Median RSS | Relative to LightView |
|---|---:|---:|---:|---:|
| LightView | 4.23 MiB | 3.15 MiB (universal) | 149.20 MiB | 1.00× |
| Tovi 2.0.4 | 5.11 MiB | 0.87 MiB (x86_64) | 408.62 MiB | 2.74× |
| qView 7.1 | 116.41 MiB | 3.19 MiB (universal) | 519.72 MiB | 3.48× |
| SimpView | 1.91 MiB | 1.10 MiB (arm64) | 795.83 MiB | 5.33× |

See [`benchmarks/results/2026-08-28/summary.md`](benchmarks/results/2026-08-28/summary.md) for method, variability, WebKit attribution, application identities, and raw-file links. The older two-app study below is retained as historical evidence; its one-shot huge-image figures are superseded by the alternating three-round corpus.

The final Direct binary was subsequently rechecked alone over three rounds (15 samples): 136.42 MiB median RSS, 134.90 MiB mean, and 118.63–142.08 MiB range, with zero descendant RSS. This remains below the accepted alternating-comparison median but does not replace that protocol.

## Historical Tovi 1.5 vs SimpView comparison

Measured on 2026-08-28 using an Apple silicon Mac running macOS 26.6.2 and Xcode 26.6.

## Inputs

- Tovi: `ideawu/Tovi-1.0` at `e4e5ff901e7471789803d3671faeb8199fd24416`
- Tovi dependency: `ideawu/soc` at `cfaf4dbeea8bff340ed90ed796e530aec4cddad0`
- SimpView: `jdpurcell/SimpView` at `d8a824f28535703471c374c75663448a609f9a8a`
- Build: Release, arm64, code signing disabled, separate DerivedData directories
- RSS input image: `SimpView/docs/screenshot.png`

The public Tovi repository builds version 1.5. It is not the installed Tovi 2.0.4 binary and does not include the later MP4 exporter.

## Compatibility adjustments for Tovi

The unmodified repository does not build with Xcode 26:

1. The repository deleted its `soc` symlink but retained absolute references to the author's `/Users/wuzuyang/Works/soc` directory. The official 2013 `ideawu/soc` repository was cloned and the project references were redirected to it.
2. Adding the whole dependency as a header search path causes its old `string.h` to shadow the system `<string.h>` on a case-insensitive filesystem. Tovi imports were changed to explicit relative paths instead.
3. Xcode 26's `iconutil` rejects the legacy iconset. The exact ten source PNG payloads were packed into a standard ICNS container after the build. No image payload was omitted from the bundle-size measurement.
4. The deployment target was raised from 10.7 to Xcode 26's minimum supported value, 10.13, through the build command.

No application behavior or optimization setting was changed.

## Size results

| Metric | Tovi | SimpView | Comparison |
|---|---:|---:|---:|
| `.app` logical bytes | 3,909,516 B (3.73 MiB) | 1,991,131 B (1.90 MiB) | Tovi 1.96× larger |
| `.app` allocated size | 3,936 KiB | 1,956 KiB | Tovi 2.01× larger |
| Main Mach-O | 462,776 B (0.44 MiB) | 1,143,512 B (1.09 MiB) | SimpView 2.47× larger |
| Bundle resources | 3,439,906 B | 845,616 B | Tovi 4.07× larger |

Both executables are thin arm64 Mach-O files. Tovi's bundle is dominated by its JavaScript themes and background images; SimpView's bundle is dominated by its Swift Mach-O and 845,616-byte app icon.

## RSS results

Each app was launched as a new process, opened the same image, allowed to settle for five seconds, and then sampled five times at 0.5-second intervals. Runs were alternated between the two apps. The values are main-process RSS only.

| Metric | Tovi | SimpView |
|---|---:|---:|
| Overall median | 98,624 KiB (96.31 MiB) | 96,800 KiB (94.53 MiB) |
| Overall mean | 98,517 KiB (96.21 MiB) | 96,841 KiB (94.57 MiB) |
| Median difference | +1,824 KiB (+1.78 MiB) | baseline |

Raw samples:

```text
Tovi run 1:     98128 98048 97952 97952 97952 KiB
SimpView run 1: 97040 97040 96960 96960 96912 KiB
Tovi run 2:     98720 98720 98624 98624 98624 KiB
SimpView run 2: 96800 96736 96736 96656 96656 KiB
Tovi run 3:     98896 98880 98880 98880 98880 KiB
SimpView run 3: 96912 96800 96800 96800 96800 KiB
```

These small-image figures are main-process RSS only and therefore are not a complete application-memory comparison. Tovi uses the legacy WebKit `WebView`; on this macOS release it reused already-running WebKit XPC processes instead of creating new PIDs, so a PID-creation check missed the WebKit-side increase.

## 12000 x 8000 JPEG RSS follow-up

The same generated `huge-12000x8000.jpg` was opened in both apps. Before launching Tovi, the already-running WebKit GPU, Networking, and WebContent processes used 44,352 KiB total. Tovi was then launched alone and sampled while frontmost; SimpView was subsequently launched fresh and sampled while frontmost.

| Metric | RSS |
|---|---:|
| Tovi main process | 119,040 KiB (116.25 MiB) |
| WebKit helper processes, gross | 176,064 KiB (171.94 MiB) |
| Tovi + WebKit, gross | 295,104 KiB (288.19 MiB) |
| WebKit helper increase over baseline | 131,712 KiB (128.63 MiB) |
| Tovi attributed total (main + helper increase) | 250,752 KiB (244.88 MiB) |
| SimpView main process | 787,536 KiB (769.08 MiB) |

On the delta-adjusted foreground first-load measure, SimpView used about 3.14 times Tovi's attributed RSS for this image. The result is state-sensitive: after being covered and left in the background, SimpView's main-process RSS later fell to about 86 MiB; bringing it forward and reopening the image raised it above 800 MiB again. Summing RSS across processes can double-count shared pages, and the WebKit helpers are shared, long-lived system processes, so the attributed Tovi total is an approximation rather than a private-footprint measurement. It is nevertheless much more representative than comparing only the two main processes.
