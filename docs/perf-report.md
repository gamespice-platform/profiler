Perf report v1: the stable, machine-readable result of one recording, written as `perf-<stamp>.json` beside the profiler's own `profile-<stamp>.json`. The profile report (docs/report-format.md) is for people and may grow keys at will; this one is for tools (Nightly's Performance tab, CI budgets, diffs between builds), so its keys and meaning only change with `schema_version`. The schema is [perf-report.schema.json](perf-report.schema.json) (draft 2020-12, `$id` https://gamespice.dev/schemas/perf-report/1.json); `python3 tools/perf_report_check.py perf-*.json` validates a file with the standard library only.

## What it holds

| Key | Content |
|---|---|
| `schema`, `schema_version` | `gamespice.perf-report`, `1` |
| `game_id`, `build`, `platform`, `role`, `scene`, `map`, `bots`, `players`, `resolution`, `gpu`, `cpu`, `os`, `renderer`, `tick_rate`, `duration_s`, `tags` | what ran, where: `platform` is `web` or `native`, `role` `client`, `server` or `standalone` |
| `frame` | count, ms stat (min, avg, p50, p95, p99, max), fps, budget, the physics/script/render/wait split |
| `budget[]` | one row per call-tree node: `id`, `path`, `parent`, `addon`, ms per frame (total and self), share of frame and budget, p95, max, calls |
| `addons[]` | self time summed per owner, with the costliest ids |
| `hitches[]` | frames well above the average: time, cause (system or `engine.<phase>`), the systems that ran (`stack`, `stack_ms`), phase split, log hints, period |
| `render` | draw calls, objects, primitives stats; texture and buffer MB; `top_draw` (materials and meshes by estimated draws and triangles) when `profiler_perf_render_scan` is on |
| `memory` | static, video, wasm heap (web), objects, nodes, orphans as start/end; growth per minute; node classes with growth; allocation counters |
| `network.by_class[]` | bytes, messages, bytes/s and the largest message per class and direction |
| `physics`, `tick`, `script`, `counters`, `loading[]`, `baseline`, `overhead_ms_per_frame`, `notes` | see the schema |

Lists are cut to `profiler_perf_top` rows (default 25; `0` keeps every row). Nothing is capped otherwise.

## Naming budget groups

A budget `id` is the name a game gave `DotFrameCost.add` (`fc.bots`, `fc.net_recv`); the engine's phases are `engine.process`, `engine.physics`, `engine.render`, `engine.wait`, and the whole frame is `frame`. Name systems `<owner>.<what>`: the first dotted segment is the addon or game that owns it. `DotProfilerBudget.register_owner("fc.net", "dot-net")` says a longer prefix belongs elsewhere (longest prefix wins). `path` is the tree path (`frame;engine.process;fc.bots`), because one id can appear under two parents.

## How a new game plugs in

1. Nothing for the basics: every recording the profiler writes also writes a perf report. Set `profiler_perf_game_id` (cvar, `DOT_PROFILER_PERF_GAME_ID`, `--profiler-perf-game-id`) or the project name is used. Role is `server` on a headless run, else `client`; `profiler_perf_role` overrides.
2. Name systems `<owner>.<what>` when calling `DotFrameCost.add`.
3. Say what the run was: `profiler.set_perf_option("map", "dust")`, `"bots"`, `"players"`, `"tags"` (a dictionary of anything else).
4. Network cost: where a message is sent or read, `DotProfilerNetCost.add(&"snapshot", DotProfilerNetCost.OUT, bytes)` (and `IN`). One bool test when no recording runs.
5. Loads: `var t := DotProfilerLoads.now()` before and `DotProfilerLoads.add("res://maps/dust.tscn", &"map", t)` after.
6. Allocation and fan-out counters: `DotProfilerCounts.add(&"emit.hit")`; they show under `memory.top_allocs` and `counters`.
7. Optional: `profiler_perf_render_scan` for the draw table (one scene walk at the end of a recording; not for a 60 FPS gate run).

## Known gaps

Per-material GPU time (the engine exposes the viewport's GPU ms only), signal fan-out without a manual counter, and per-class network cost from `dot-net` itself (the call in step 4 has to be made by the sender; see Nightly perf-profiler-gaps-1).
