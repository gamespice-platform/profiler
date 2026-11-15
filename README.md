Finds the cause of frame spikes. When a frame runs over budget it logs which system took the time and what that system was doing, names causes that repeat on a beat, draws an overlay of the top costs, and writes JSON and text reports. It can run headless for a nightly performance budget.

Depends on dot-core only (`DotFrameCost`, `DotHitchLog`, `DotSpaceQuery`, API level 30 or later). dot-console, dot-menu, dot-server and dot-server-query are used when present.

## Use

```gdscript
var prof := DotProfiler.new()
prof.config = DotProfilerConfig.new()
add_child(prof)
prof.bind_console(console_local)   # profiler_* cvars, record 30, profiler_stop, profiler_report
```

Systems report their cost:

```gdscript
var t := DotFrameCost.now()
_rebuild_paths()
DotFrameCost.add(&"navigation.rebuild", t, "%d paths" % n)
```

A spike then logs a warning such as:

```
frame 41.2 ms over 33.0 ms budget: t=12.50s 41.2 ms  navigation.rebuild (52 paths)  [phys 1.0 script 38.1 render 1.5 wait 0.6] repeats every 0.50 s (7 of 7 gaps)
```

## Settings

Everything is off by default.

| Setting | Effect |
| --- | --- |
| `profiler_enabled 1` | Watch for spikes. |
| `profiler_overlay 1` | Draw the overlay. |
| `record 30` | Record 30 seconds to `user://profiles/<stamp>.json`, `.txt` and `.folded`. |
| `profiler_timeline 1` | Record every frame, spikes flagged with what ran in them. |
| `profiler_render_detail 1` | Texture and buffer memory, draw split, render CPU/GPU ms. |
| `profiler_groups bots:fc.bot` | Unit counts per frame and each system's cost per unit. |
| `profiler_census 1` | Node classes that grew. |
| `profiler_script_top 30` | GDScript functions by self time (run with `-d`). |
| `profiler_reference <path.json>` | Diff each written report against that file (`.diff.txt`). |
| `profiler_compare a.json b.json` | Diff two reports; one path is compared with the newest. |

`prof.enable_capture_key()` makes F10 start and stop a capture with the call tree, physics ticks, queries, engine monitors and worst frames. All settings: [docs/design.md](docs/design.md#configuration).

Every report starts with a `context` (OS, CPU, GPU, Godot build, window, tick rate, game commit, launch arguments, changed console variables). Add your own with `prof.add_context("game", func(): return {...})`, and native timers with `prof.add_recording_hook("native", begin, end)`. To compare files outside the game: `tools/profile_compare.py baseline.json new.json --diff` (ignores changes under a 5% noise floor).

## Dedicated server

`DotProfilerServer.new().install(prof)` adds admin-only commands to dot-server's console and RCON: `sv_profiler_record`, `sv_profiler_stop`, `sv_profiler_status`, and metric commands (frame, hitches, systems, memory, net, or all as one JSON line). Recordings go to `<log_directory>/profiles`.

## Docs

| File | Covers |
| --- | --- |
| [docs/design.md](docs/design.md) | The pieces, configuration and cvars, instrumenting a system. |
| [docs/report-format.md](docs/report-format.md) | Report JSON keys, call tree, folded stacks, compare. |
| [docs/deep-mode.md](docs/deep-mode.md) | Native samples with perf. |
| [docs/runner.md](docs/runner.md) | The headless runner and its `PERF` line. |
| [docs/menu.md](docs/menu.md) | The settings menu's Performance section. |
| [docs/server.md](docs/server.md) | Server commands, cvars and query keys. |

## Testing

Run the scenes in `examples/` (`profiler_selftest`, `profiler_detail_selftest`, `profiler_context_selftest`) headless with Godot, and `python3 tools/profile_compare_test.py` for the compare tool. The headless budget runner is `addons/dot_profiler/tools/dot_profiler_run.tscn`; see [docs/runner.md](docs/runner.md).

## Status and licence

Part of the TMC **dot-\*** family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/gamespice-platform/profiler/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the [Gamespice](https://gamespice.net) platform is the web back end; you can use your own instead of Gamespice's.
