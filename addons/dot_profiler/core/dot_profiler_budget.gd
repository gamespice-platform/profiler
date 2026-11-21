class_name DotProfilerBudget
extends RefCounted

## The stable naming of budget groups in the perf report (docs/perf-report.md). A budget row's [code]id[/code] is the
## system or span name a game gave DotFrameCost; the engine's own phases are [code]engine.process[/code],
## [code]engine.physics[/code], [code]engine.render[/code] and [code]engine.wait[/code]. Its [code]parent[/code] is the
## row above it in the call tree and its [code]addon[/code] the owner: the longest registered prefix, else the
## first dotted segment of the id ([code]fc.bots[/code] is [code]fc[/code]).

const ENGINE_PHASES := ["process", "physics", "render", "wait", "scripts", "step"]

static var _owners: Dictionary = {}


## Says that every id starting with [param prefix] belongs to [param addon] (longest prefix wins).
static func register_owner(prefix: String, addon: String) -> void:
	_owners[prefix] = addon


## Forgets every registered owner.
static func clear_owners() -> void:
	_owners = {}


## The stable id of a tree row called [param row_name] at [param depth].
static func id_for(row_name: String, depth: int) -> String:
	if depth == 0:
		return "frame"
	if depth <= 2 and ENGINE_PHASES.has(row_name):
		return "engine." + row_name
	return row_name


## The addon that owns [param id].
static func owner_of(id: String) -> String:
	if id == "frame" or id.begins_with("engine."):
		return "engine"
	var best := ""
	for p: String in _owners:
		if id.begins_with(p) and p.length() > best.length():
			best = p
	if best != "":
		return _owners[best]
	var dot := id.find(".")
	return id.substr(0, dot) if dot > 0 else id


## Budget rows from a report's tree: [code]path[/code] is the tree path, [param top] 0 keeps every row.
static func rows(tree: Array, frame_ms: float, budget_ms: float, top: int) -> Array:
	var ids: Dictionary = {}
	var out: Array = []
	for t: Dictionary in tree:
		var depth: int = int(t.get("depth", 0))
		var id := id_for(String(t.get("name", "")), depth)
		var path := String(t.get("path", id))
		var parent_path := path.rsplit(";", true, 1)[0] if path.contains(";") else ""
		ids[path] = id
		var ms: float = float(t.get("ms", 0.0))
		var row := {
			"id": id, "path": path, "parent": String(ids.get(parent_path, "")), "addon": owner_of(id),
			"ms_per_frame": ms, "self_ms_per_frame": float(t.get("self_ms", 0.0)),
			"pct_frame": ms / frame_ms * 100.0 if frame_ms > 0.0 else 0.0,
			"p95_ms": float(t.get("p95_ms", 0.0)), "max_ms": float(t.get("max_ms", 0.0)),
			"calls_per_frame": float(t.get("calls", 0.0)), "per": "frame"}
		if budget_ms > 0.0:
			row["pct_budget"] = ms / budget_ms * 100.0
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms_per_frame > b.ms_per_frame)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out


## Per-addon totals from the self time of [param rows] (so nested rows are not counted twice): [{addon, ms_per_frame, pct_frame, top}].
static func addons(rows_in: Array, frame_ms: float, top: int) -> Array:
	var sums: Dictionary = {}
	var best: Dictionary = {}
	for r: Dictionary in rows_in:
		var a: String = r.addon
		sums[a] = float(sums.get(a, 0.0)) + float(r.self_ms_per_frame)
		if not best.has(a) or float(best[a].self_ms_per_frame) < float(r.self_ms_per_frame):
			best[a] = r
	var out: Array = []
	for a: String in sums:
		out.append({"addon": a, "ms_per_frame": sums[a], "pct_frame": sums[a] / frame_ms * 100.0 if frame_ms > 0.0 else 0.0, "top": [best[a].id]})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.ms_per_frame > y.ms_per_frame)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out
