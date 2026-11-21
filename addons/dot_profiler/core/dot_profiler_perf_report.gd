class_name DotProfilerPerfReport
extends RefCounted

## The stable machine-readable report, version 1 (docs/perf-report.md, schema docs/perf-report.schema.json): one
## recording's frame percentiles, budget rows with addon attribution, hitches with their responsible systems, render,
## memory, network per class, physics, script split and loads. [method build] converts the profiler's own report
## (DotProfilerReport) plus what [param opts] adds; [method write] saves [code]perf-<stamp>.json[/code];
## [method problems] checks a report against the required keys.

const SCHEMA := "gamespice.perf-report"
const VERSION := 1


## The perf report for [param r] (a DotProfilerReport). [param opts]: game_id, role, platform, top (0 = all rows),
## map, bots, players, tags, network (rows), render_top (rows), loading (rows), wasm_heap_mb, baseline (dict).
static func build(r: Dictionary, opts: Dictionary) -> Dictionary:
	var ctx: Dictionary = r.get("context", {})
	var mach: Dictionary = ctx.get("machine", {})
	var bld: Dictionary = ctx.get("build", {})
	var top: int = int(opts.get("top", 0))
	var fs: Dictionary = r.get("frame_stats", {})
	var frame_stat: Dictionary = fs.get("frame", {"avg": float(r.get("p50_ms", 0.0)), "max": float(r.get("worst_ms", 0.0))})
	var frame_ms: float = float(frame_stat.get("avg", 0.0))
	var budget_ms: float = float(r.get("budget_ms", 0.0))
	var out := {
		"schema": SCHEMA, "schema_version": VERSION,
		"made_utc": Time.get_datetime_string_from_system(true) + "Z",
		"game_id": String(opts.get("game_id", "")),
		"build": {"commit": String(bld.get("commit", "unknown")), "branch": String(bld.get("branch", "")),
			"version": String(bld.get("version", "")), "godot": String(mach.get("godot", "")), "debug_build": bool(mach.get("debug_build", false))},
		"platform": String(opts.get("platform", "native")), "role": String(opts.get("role", "standalone")),
		"scene": String(r.get("scene", "")), "duration_s": float(r.get("wall_s", r.get("seconds", 0.0))),
		"frame": {"count": int(r.get("frames", 0)), "ms": frame_stat, "budget_ms": budget_ms,
			"fps_avg": 1000.0 / frame_ms if frame_ms > 0.0 else 0.0}}
	for k: String in ["map", "bots", "players", "tags"]:
		if opts.has(k):
			out[k] = opts[k]
	for pair: Array in [["resolution", "window"], ["gpu", "gpu"], ["cpu", "cpu"], ["os", "os"], ["renderer", "renderer"], ["tick_rate", "tick_rate"]]:
		if mach.has(pair[1]):
			out[pair[0]] = mach[pair[1]]
	var phases := {}
	for ph: String in ["physics", "script", "render", "wait"]:
		if fs.has(ph):
			phases[ph] = fs[ph]
	out.frame["phases"] = phases
	var rows := DotProfilerBudget.rows(r.get("tree", []), frame_ms, budget_ms, top)
	if not rows.is_empty():
		out["budget"] = rows
		out["addons"] = DotProfilerBudget.addons(DotProfilerBudget.rows(r.get("tree", []), frame_ms, budget_ms, 0), frame_ms, top)
	var pt: Dictionary = r.get("physics_ticks", {})
	if not pt.is_empty():
		out["tick"] = {"rate": float(pt.get("ticks_per_sec", 0.0)), "ticks": int(pt.get("ticks", 0)), "dropped": int(pt.get("dropped_ticks", 0)),
			"catch_up_frames": int(pt.get("catch_up_frames", 0))}
	out["hitches"] = _hitches(r.get("spikes", []), top)
	var mon: Dictionary = r.get("monitors", {})
	out["render"] = _render(mon, opts)
	out["memory"] = _memory(mon, r, opts)
	if opts.has("network"):
		out["network"] = {"by_class": opts.network}
	var phys := {}
	for k: String in ["physics_3d_active", "physics_3d_pairs", "physics_3d_islands"]:
		if mon.has(k):
			phys[k.trim_prefix("physics_3d_")] = mon[k]
	if not phys.is_empty():
		out["physics"] = phys
	var total_ms: float = frame_ms
	var script_ms: float = float(fs.get("script", {}).get("avg", 0.0))
	if total_ms > 0.0:
		out["script"] = {"script_ms_per_frame": script_ms, "script_pct": script_ms / total_ms * 100.0}
	var counts: Dictionary = r.get("engine", {}).get("counts", {})
	if not counts.is_empty():
		out["counters"] = counts
	if opts.has("loading") and not (opts.loading as Array).is_empty():
		out["loading"] = opts.loading
	if opts.has("baseline"):
		out["baseline"] = opts.baseline
	out["overhead_ms_per_frame"] = float(r.get("overhead", {}).get("on_frame_avg_ms", 0.0))
	return out


static func _hitches(spikes: Array, top: int) -> Array:
	var out: Array = []
	for s: Dictionary in spikes:
		var systems: Dictionary = s.get("systems", {})
		var names: Array = systems.keys()
		names.sort_custom(func(a: String, b: String) -> bool: return systems[a] > systems[b])
		var stack: Array = []
		var stack_ms: Array = []
		for n: String in names.slice(0, 5):
			stack.append(n)
			stack_ms.append(systems[n])
		out.append({"t": float(s.get("t", 0.0)), "ms": float(s.get("ms", 0.0)), "cause": String(s.get("cause", "")),
			"what": String(s.get("what", "")), "stack": stack, "stack_ms": stack_ms, "hints": s.get("hints", []),
			"phases": {"physics": s.get("physics", 0.0), "script": s.get("script", 0.0), "render": s.get("render", 0.0), "wait": s.get("wait", 0.0)},
			"period": String(s.get("period", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out


static func _render(mon: Dictionary, opts: Dictionary) -> Dictionary:
	var out := {}
	for k: String in ["draw_calls", "primitives", "objects_drawn"]:
		if mon.has(k):
			out["objects" if k == "objects_drawn" else k] = mon[k]
	for k: String in ["texture_mb", "buffer_mb", "video_mb"]:
		if mon.has(k):
			out[k] = (mon[k] as Dictionary).get("avg", 0.0)
	if opts.has("render_top"):
		out["top_draw"] = opts.render_top
	return out


static func _num(v: Variant) -> float:
	return float(v) if v is float or v is int else 0.0


static func _memory(mon: Dictionary, r: Dictionary, opts: Dictionary) -> Dictionary:
	var out := {}
	var g: Dictionary = r.get("growth", {})
	for k: String in ["static_mb", "video_mb", "objects", "nodes", "orphan_nodes"]:
		if not mon.has(k):
			continue
		var m: Dictionary = mon[k]
		var row := {"end": _num(m.get("avg"))}
		if g.get(k) is Dictionary:
			row = {"start": _num(g[k].get("first")), "end": _num(g[k].get("last"))}
		if k == "static_mb":
			row["peak"] = _num(m.get("max"))
		if not k.ends_with("_mb"):
			for e: String in row:
				row[e] = int(row[e])
		out[k] = row
	var growth := {}
	for k: String in g:
		if g[k] is Dictionary and (g[k] as Dictionary).has("per_min"):
			growth[k] = g[k].per_min
	if not growth.is_empty():
		out["growth_per_min"] = growth
	if opts.has("wasm_heap_mb"):
		out["wasm_heap_mb"] = {"end": opts.wasm_heap_mb}
	var classes: Array = []
	for c: Dictionary in r.get("census", {}).get("classes", []):
		classes.append({"class": c["class"], "count": int(c.get("end", 0)), "delta": int(c.get("delta", 0))})
	if not classes.is_empty():
		out["top_classes"] = classes.slice(0, int(opts.get("top", 0))) if int(opts.get("top", 0)) > 0 else classes
	var allocs: Array = []
	var frames := maxi(int(r.get("frames", 1)), 1)
	var counts: Dictionary = r.get("engine", {}).get("counts", {})
	for n: String in counts:
		var c: Variant = counts[n]
		var total: float = float(c.get("total", 0.0)) if c is Dictionary else float(c)
		allocs.append({"name": n, "total": int(total), "per_frame": total / frames})
	allocs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.total > b.total)
	if not allocs.is_empty():
		out["top_allocs"] = allocs.slice(0, int(opts.get("top", 0))) if int(opts.get("top", 0)) > 0 else allocs
	return out


## The WebAssembly heap in MB on a web export, else -1.0 (nothing to read). Reads the JS heap through JavaScriptBridge.
static func wasm_heap_mb() -> float:
	if not OS.has_feature("web"):
		return -1.0
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	var v: Variant = bridge.call("eval", "(typeof HEAP8!=='undefined'&&HEAP8.length)||(Module&&Module.HEAP8&&Module.HEAP8.length)||0", true)
	return float(v) / 1048576.0 if v != null else -1.0


## The costliest materials, meshes and node classes under [param root]: 3D meshes counted by instance, surfaces and
## triangles. Walks the tree once (call it at the end of a capture, not per frame). [param top] 0 keeps all.
static func render_top(root: Node, top: int) -> Array:
	var mats: Dictionary = {}
	var meshes: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var mesh_name: String = mi.mesh.resource_path if mi.mesh.resource_path != "" else mi.mesh.get_class()
		var tris := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX] if not arr.is_empty() else null
			var vtx: Variant = arr[Mesh.ARRAY_VERTEX] if not arr.is_empty() else null
			var st: int = (idx as PackedInt32Array).size() / 3 if idx != null else ((vtx as PackedVector3Array).size() / 3 if vtx != null else 0)
			tris += st
			var m: Material = mi.get_active_material(s)
			var mname: String = (m.resource_path if m.resource_path != "" else m.get_class()) if m != null else "(none)"
			var mr: Dictionary = mats.get(mname, {"kind": "material", "name": mname, "instances": 0, "surfaces": 0, "triangles": 0})
			mr.instances += 1
			mr.surfaces += 1
			mr.triangles += st
			mats[mname] = mr
		var row: Dictionary = meshes.get(mesh_name, {"kind": "mesh", "name": mesh_name, "instances": 0, "surfaces": mi.mesh.get_surface_count(), "triangles": 0})
		row.instances += 1
		row.triangles += tris
		meshes[mesh_name] = row
	var out: Array = mats.values() + meshes.values()
	for r: Dictionary in out:
		r["est_draws"] = r.instances * maxi(int(r.surfaces), 1) if r.kind == "mesh" else r.instances
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.est_draws > b.est_draws)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out


## Required-key and type problems of [param p] against the v1 schema (an empty array is a valid report).
static func problems(p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in ["schema", "schema_version", "game_id", "build", "platform", "role", "scene", "duration_s", "frame"]:
		if not p.has(k):
			out.append("missing " + k)
	if p.get("schema", SCHEMA) != SCHEMA or int(p.get("schema_version", VERSION)) != VERSION:
		out.append("not %s v%d" % [SCHEMA, VERSION])
	if not ["web", "native"].has(p.get("platform", "native")):
		out.append("platform must be web or native")
	if not ["client", "server", "standalone"].has(p.get("role", "client")):
		out.append("role must be client, server or standalone")
	if p.get("game_id", "x") == "":
		out.append("game_id is empty")
	var f: Dictionary = p.get("frame", {})
	if not f.has("count") or not f.has("ms") or not (f.get("ms", {}) as Dictionary).has("avg"):
		out.append("frame needs count and ms.avg/max")
	return out


## Writes [param p] as [code]perf-<stamp>.json[/code] under [param dir] (made if missing); the value is the path.
static func write(p: Dictionary, dir: String) -> DotResult:
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and not DirAccess.dir_exists_absolute(dir):
		return DotResult.fail(DotError.CODE_IO, "Cannot create %s." % dir)
	var path := dir.path_join("perf-%s-%d.json" % [Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", ""), Time.get_ticks_msec() % 1000])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "Cannot write %s." % path)
	f.store_string(JSON.stringify(p, "\t", true))
	f.close()
	return DotResult.success(path)


## Builds, checks and writes the perf report (docs/perf-report.md) for [param report] beside the recording and returns
## its path, or "" on failure (logged, not fatal). [param extra] is the game's options (map, bots, players, tags).
static func save(tree: SceneTree, config: DotProfilerConfig, report: Dictionary, net_rows: Array, load_rows: Array,
		extra: Dictionary, channel: StringName) -> String:
	var opts := {"game_id": config.perf_game_id if config.perf_game_id != "" else String(ProjectSettings.get_setting("application/config/name", "")),
		"platform": "web" if OS.has_feature("web") else "native", "top": config.perf_top, "loading": load_rows,
		"role": config.perf_role if config.perf_role != "" else ("server" if DisplayServer.get_name() == "headless" else "client")}
	if not net_rows.is_empty():
		opts["network"] = net_rows
	if config.perf_render_scan and tree.current_scene != null:
		opts["render_top"] = render_top(tree.root, config.perf_top)
	var heap := wasm_heap_mb()
	if heap >= 0.0:
		opts["wasm_heap_mb"] = heap
	for k: String in extra:
		opts[k] = extra[k]
	var perf := build(report, opts)
	var bad := problems(perf)
	if not bad.is_empty():
		DotLog.warn(channel, "perf report is invalid: %s" % ", ".join(bad))
	var res := write(perf, config.record_dir)
	if not res.ok:
		DotLog.warn(channel, "perf report not saved: %s" % res.error.message)
		return ""
	DotLog.info(channel, "perf report saved to %s" % ProjectSettings.globalize_path(res.value))
	return res.value
