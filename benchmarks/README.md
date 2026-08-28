# Benchmarking

Build both Release variants first, close every viewer being measured, and run:

```bash
./scripts/benchmark-suite.sh /absolute/path/to/fixture.jpg
```

The suite alternates application order for three rounds and records five settled RSS samples per run. `main_rss_kib` is the launched process; `child_rss_kib` is its descendant-process total. Tovi also records the before/after total of shared `com.apple.WebKit.*` processes because those helpers can predate Tovi and cannot be attributed by PID ancestry alone.

RSS contains shared pages and is not private footprint. The raw TSV files are the evidence; summaries must state fixture hash, active architecture, macOS build, foreground state, settle time, and helper attribution limitations.
