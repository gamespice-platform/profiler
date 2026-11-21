Perf report v1.1 (`schema_version` 1, `schema_minor` 1; additive, every 1.0 report is still valid): the stable, machine-readable result of one recording, written as `perf-<stamp>.json` beside the profiler's own `profile-<stamp>.json`. The profile report (docs/report-format.md) is for people and may grow keys at will; this one is for tools (Nightly's Performance tab, CI budgets, diffs between builds), so its keys and meaning only change with `schema_version`. The schema is [perf-report.schema.json](perf-report.schema.json) (draft 2020-12, `$id` https://gamespice.dev/schemas/perf-report/1.json); `python3 tools/perf_report_check.py perf-*.json` validates a file with the standard library only.

## What it holds

| Key | Content |
|---|---|
| `schema`, `schema_version`, `schema_minor` | `gamespice.perf-report`, `1`, `1` (absent in 1.0 reports) |
| `game_id`, `build`, `platform`, `role`, `scene`, `map`, `bots`, `players`, `resolution`, `gpu`, `cpu`, `os`, `renderer`, `tick_rate`, `duration_s`, `tags` | what ran, where: `platform` is `web` or `native`, `role` `client`, `server` or `standalone` |
| `frame` | count, ms stat (min, avg, p50, p95, p99, max), fps, budget, the physics/script/render/wait split |
| `budget[]` | one row per call-tree node: `id`, `path`, `parent`, `addon`, ms per frame (total and self), share of frame and budget, p95, max, calls |
| `addons[]` | self time summed per owner, with the costliest ids |
| `hitches[]` | frames well above the average: time, cause (system or `engine.<phase>`), the systems that ran (`stack`, `stack_ms`), phase split, log hints, period |
| `render` | draw calls, objects, primitives stats; texture and buffer MB; `top_draw` (materials and meshes by estimated draws and triangles) when `profiler_perf_render_scan` is on; with `profiler_perf_render_estimate` (default on) rows carry `est_cost` and `cost_estimate` says it is an estimate |
| `memory` | static, video, wasm heap (web), objects, nodes, orphans as start/end; growth per minute; node classes with growth; allocation counters |
| `network.by_class[]` | bytes, messages, bytes/s and the largest message per class and direction |
| `signals.fanout[]` | per signal: emits, receivers (max, average), deliveries (emits x receivers) and deliveries per second, from `DotProfilerSignals`; cut to `profiler_perf_signal_top` |
| `baseline` | what moved against the report named by `profiler_perf_baseline`: rows beyond `profiler_perf_baseline_noise_pct`, each `worse` or `better`, with the reference's commit and time and the counts |
| `physics`, `tick`, `script`, `counters`, `loading[]`, `overhead_ms_per_frame`, `notes` | see the schema |

Lists are cut to `profiler_perf_top` rows (default 25; `0` keeps every row). Nothing is capped otherwise.

## Naming budget groups

A budget `id` is the name a game gave `DotFrameCost.add` (`fc.bots`, `fc.net_recv`); the engine's phases are `engine.process`, `engine.physics`, `engine.render`, `engine.wait`, and the whole frame is `frame`. Name systems `<owner>.<what>`: the first dotted segment is the addon or game that owns it. `DotProfilerBudget.register_owner("fc.net", "dot-net")` says a longer prefix belongs elsewhere (longest prefix wins). `path` is the tree path (`frame;engine.process;fc.bots`), because one id can appear under two parents.

## How a new game plugs in

1. Nothing for the basics: every recording the profiler writes also writes a perf report. Set `profiler_perf_game_id` (cvar, `DOT_PROFILER_PERF_GAME_ID`, `--profiler-perf-game-id`) or the project name is used. Role is `server` on a headless run, else `client`; `profiler_perf_role` overrides.
2. Name systems `<owner>.<what>` when calling `DotFrameCost.add`.
3. Say what the run was: `profiler.set_perf_option("map", "dust")`, `"bots"`, `"players"`, `"tags"` (a dictionary of anything else).
4. Network cost: where a message is sent or read, `DotProfilerNetCost.add(&"snapshot", DotProfilerNetCost.OUT, bytes)` (and `IN`). One bool test when no recording runs.
5. Loads: `var t := DotProfilerLoads.now()` before and `DotProfilerLoads.add("res://maps/dust.tscn", &"map", t)` after.
6. Signal fan-out: `DotProfilerSignals.emitted(self, &"health_changed")` next to the emit (reads the connection count; or `note(&"name", receivers)`). Allocation counters: `DotProfilerCounts.add(&"emit.hit")`; they show under `memory.top_allocs` and `counters`.
7. Optional: `profiler_perf_render_scan` for the draw table (one scene walk at the end of a recording; not for a 60 FPS gate run).

## Baseline

Set `profiler_perf_baseline` (a path to an earlier `perf-*.json`) and every new report gets a `baseline` section: frame ms, budget and addon ms per frame, network bytes per second and render draws that moved by more than `profiler_perf_baseline_noise_pct` (default 5; `0` lists every difference), each marked `worse` or `better`. A baseline that cannot be read is logged and skipped. `profiler_perf_signal_top` cuts the fan-out table and `profiler_perf_render_estimate` turns the cost estimate on or off. Every numeric limit here takes `0` for unlimited and a negative value fails validation.

## GPU time

With `profiler_perf_gpu_time` on (the default) the report gets `render.gpu`. On Forward+ and Mobile with a real display it holds `source: "measured"`: per viewport (the root and every SubViewport, from `viewport_get_measured_render_time_gpu/cpu`) `{name, gpu_ms, cpu_ms}`, and per render pass (the renderer's captured RenderingDevice timestamps) `{name, avg_ms, max_ms, frames}`. On the web build, Compatibility and headless runs the engine has no timers: `source: "unavailable"` with a `why`, and only the labelled estimate remains. The engine has no per-material GPU timer, so each `top_draw` material row gets `est_gpu_ms`, the measured frame GPU ms shared by `est_draws`: an estimate, labelled as one.

## Call-trace artifacts

With `profiler_perf_trace` on (the default) each perf report is joined by `perf-<stamp>.trace.html` (a self-contained SVG icicle graph: width is time, hover for name and share) and `perf-<stamp>.trace.png` (a thumbnail of the same layout), both made from the recording's folded stacks. `profiler_perf_trace_max_boxes` (2000; 0 = unlimited) keeps the widest boxes so files stay small; `profiler_perf_trace_png_width` (480; 0 = no PNG). Nightly renders its own icicle from the uploaded folded stacks; these files are the copy that travels with the run on disk and in CI artifacts.

## Uploading

Set `profiler_perf_upload_url` (cvar, `DOT_PROFILER_PERF_UPLOAD_URL`, `--profiler-perf-upload-url`) to Nightly's base URL and a finished perf report plus its folded stacks is POSTed to `/api/perf/ingest` (JSON envelope `{report, folded}`, scope in the query). It is off when the URL is empty. The Bearer token is read from the environment variable `NIGHTLY_PERF_TOKEN` or the first line of the file named by `profiler_perf_upload_token_file`; it has no cvar and no command-line form (argv shows in process lists), is only sent in the Authorization header and is never logged. The upload uses HTTPRequest, so it works in a web export when the panel allows the page's origin. The result arrives on the `perf_uploaded(ok, status, message)` signal and in the log; a failure is reported, never retried.

`python3 tools/perf_upload.py perf-<stamp>.json --url <nightly> [--folded rec.folded] [--token-file path]` does the same from a shell or CI (token from the environment or the file, never an argument); `tools/perf_upload_test.py` checks it against a local server.

## Open-ended capture

`profiler_capture_seconds` 0 records until the capture key is pressed again or `profiler_stop` runs (`start_recording(0.0, true)` from code); there is no length limit. The report's `seconds` is the real length. Native deep sampling needs a length and stays off for an open-ended recording. A negative value fails validation.

## Known gaps

- Real per-material GPU time: the engine has no such timer, so `est_gpu_ms` (and `est_cost`, draws plus triangles over 1000, where no GPU time was measured) is an estimate, labelled as one. Measured passes are not available on web or Compatibility.
- Per-class network cost from `dot-net` is reported through `DotNetCostProbe` (found by name, no dependency). Message types dot-net does not send through its manager (a game's own transport) still need the step 4 call.
