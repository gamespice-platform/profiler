class_name GSProfilerPerfBaseline
extends RefCounted

## The perf report's [code]baseline[/code] section (report v1.1): what moved between a reference perf report and this one, beyond a noise floor.
## Compared: frame ms stats, budget and addon ms per frame, network bytes per second per class, render draw calls and primitives, fps.

## Keys where a higher number is better; every other compared key is a cost.
const HIGHER_IS_BETTER := ["frame.fps_avg"]


## The baseline section for [param cur] against [param ref] (both perf reports). [param noise_pct] is the change below which a row is dropped (0 lists every difference); [param against] names the reference.
static func diff(cur: Dictionary, ref: Dictionary, noise_pct: float, against: String) -> Dictionary:
	var a := flatten(ref)
	var b := flatten(cur)
	var changed: Array = []
	var worse := 0
	var better := 0
	for key: String in b:
		if not a.has(key):
			continue
		var va: float = a[key]
		var vb: float = b[key]
		var delta := vb - va
		if is_zero_approx(delta):
			continue
		var pct := delta / absf(va) * 100.0 if va != 0.0 else (100.0 if delta > 0.0 else -100.0)
		if absf(pct) < noise_pct:
			continue
		var higher_better := HIGHER_IS_BETTER.has(key)
		var is_worse := (delta < 0.0) if higher_better else (delta > 0.0)
		worse += 1 if is_worse else 0
		better += 0 if is_worse else 1
		changed.append({"key": key, "a": va, "b": vb, "delta": delta, "pct": pct, "direction": "worse" if is_worse else "better"})
	changed.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return absf(x.pct) > absf(y.pct))
	return {"against": against, "against_commit": String(ref.get("build", {}).get("commit", "")), "against_made_utc": String(ref.get("made_utc", "")),
		"noise_pct": noise_pct, "compared": b.size(), "worse": worse, "better": better, "changed": changed}


## Reads the perf report at [param path]; a failed read is a failed result, so a bad [code]profiler_perf_baseline[/code] is loud.
static func load_report(path: String) -> GSResult:
	if not FileAccess.file_exists(path):
		return GSResult.fail(GSError.CODE_IO, "Baseline report %s does not exist." % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or (parsed as Dictionary).get("schema", "") != "gamespice.perf-report":
		return GSResult.fail(GSError.CODE_INVALID, "Baseline %s is not a perf report." % path)
	return GSResult.success(parsed)


## The comparable numbers of a perf report, key to value.
static func flatten(p: Dictionary) -> Dictionary:
	var out := {}
	var f: Dictionary = p.get("frame", {})
	for k: String in (f.get("ms", {}) as Dictionary):
		if f.ms[k] is float or f.ms[k] is int:
			out["frame.ms." + k] = float(f.ms[k])
	if f.has("fps_avg"):
		out["frame.fps_avg"] = float(f.fps_avg)
	for row: Dictionary in p.get("budget", []):
		out["budget." + String(row.get("id", ""))] = float(row.get("ms_per_frame", 0.0))
	for row: Dictionary in p.get("addons", []):
		out["addon." + String(row.get("addon", ""))] = float(row.get("ms_per_frame", 0.0))
	for row: Dictionary in p.get("network", {}).get("by_class", []):
		out["net.%s.%s" % [row.get("class", ""), row.get("dir", "")]] = float(row.get("bytes_per_s", 0.0))
	var r: Dictionary = p.get("render", {})
	for k: String in ["draw_calls", "primitives"]:
		if r.get(k) is Dictionary and (r[k] as Dictionary).has("avg"):
			out["render." + k] = float(r[k].avg)
	return out
