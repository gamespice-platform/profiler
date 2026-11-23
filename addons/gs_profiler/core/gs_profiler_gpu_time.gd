class_name GSProfilerGpuTime
extends RefCounted

## Measured GPU time per viewport and per render pass while recording (perf report `render.gpu`).
## Viewports: viewport_get_measured_render_time_gpu/_cpu for the root and every SubViewport found at start. Passes: the renderer's timestamps on the main RenderingDevice (Forward+, Mobile); each pass costs the gap to the stamp before it.
## Where none exists (Compatibility, web, headless) [method report] says [code]source: "unavailable"[/code] and the report keeps the labelled estimate; materials stay an estimate ([method apportion]).

const SOURCE_MEASURED := "measured"
const SOURCE_UNAVAILABLE := "unavailable"
const WHY_NONE := "no RenderingDevice: Compatibility renderer, a web export or a headless run"

## [{name, rid}] viewports read each frame; filled by [method begin].
var viewports: Array[Dictionary] = []
var _rd: RenderingDevice = null
var _vp_cpu: Dictionary = {}
var _vp_gpu: Dictionary = {}
var _pass_sum: Dictionary = {}
var _pass_max: Dictionary = {}
var _pass_n: Dictionary = {}
var _frames := 0
var _gpu_frames := 0


## True when this build can measure passes at all (a RenderingDevice exists: Forward+ or Mobile on a real display).
static func available() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null


## Starts measuring [param root] and every SubViewport below it, on top of [param main] (the root viewport's RID).
func begin(root: Node, main: RID) -> void:
	viewports.clear()
	if root != null:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is SubViewport:
				viewports.append({"name": String(n.get_path()), "rid": (n as SubViewport).get_viewport_rid()})
	viewports.push_front({"name": "root", "rid": main})
	for v: Dictionary in viewports:
		if (v.rid as RID).is_valid():
			RenderingServer.viewport_set_measure_render_time(v.rid, true)
	_rd = RenderingServer.get_rendering_device() if available() else null


## Reads this frame's numbers. Call once per frame after the frame's render.
func sample() -> void:
	_frames += 1
	for v: Dictionary in viewports:
		var rid: RID = v.rid
		if not rid.is_valid():
			continue
		var n: String = v.name
		_vp_cpu[n] = float(_vp_cpu.get(n, 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(rid)
		_vp_gpu[n] = float(_vp_gpu.get(n, 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
	if _rd == null:
		return
	var count := _rd.get_captured_timestamps_count()
	if count < 2:
		return
	_gpu_frames += 1
	var prev := _rd.get_captured_timestamp_gpu_time(0)
	for i in range(1, count):
		var t := _rd.get_captured_timestamp_gpu_time(i)
		add_pass(_rd.get_captured_timestamp_name(i), float(t - prev) / 1.0e6)
		prev = t


## Adds one pass of [param ms] to the tallies (public so a suite can feed it known numbers).
func add_pass(pass_name: String, ms: float) -> void:
	_pass_sum[pass_name] = float(_pass_sum.get(pass_name, 0.0)) + ms
	_pass_max[pass_name] = maxf(float(_pass_max.get(pass_name, 0.0)), ms)
	_pass_n[pass_name] = int(_pass_n.get(pass_name, 0)) + 1


## Adds one frame of one viewport's [param gpu_ms] and [param cpu_ms] (public for suites, like [method add_pass]).
func add_viewport(vp_name: String, gpu_ms: float, cpu_ms: float) -> void:
	_frames += 1
	_vp_gpu[vp_name] = float(_vp_gpu.get(vp_name, 0.0)) + gpu_ms
	_vp_cpu[vp_name] = float(_vp_cpu.get(vp_name, 0.0)) + cpu_ms


## The `render.gpu` object: source, why when unavailable, viewports and passes ([param top] rows each; 0 keeps every row).
func report(top: int) -> Dictionary:
	var has_pass := not _pass_sum.is_empty()
	var has_vp := false
	for n: String in _vp_gpu:
		has_vp = has_vp or float(_vp_gpu[n]) > 0.0
	if not has_pass and not has_vp:
		return {"source": SOURCE_UNAVAILABLE, "why": WHY_NONE if not available() else "the renderer reported no timestamps", "basis": "estimate"}
	var vp_frames := maxi(_frames, 1)
	var vps: Array = []
	for n: String in _vp_gpu:
		vps.append({"name": n, "gpu_ms": float(_vp_gpu[n]) / vp_frames, "cpu_ms": float(_vp_cpu.get(n, 0.0)) / vp_frames})
	vps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.gpu_ms > b.gpu_ms)
	var passes: Array = []
	for n: String in _pass_sum:
		passes.append({"name": n, "avg_ms": float(_pass_sum[n]) / float(maxi(int(_pass_n[n]), 1)), "max_ms": _pass_max[n], "frames": _pass_n[n]})
	passes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.avg_ms > b.avg_ms)
	if top > 0:
		if vps.size() > top:
			vps.resize(top)
		if passes.size() > top:
			passes.resize(top)
	return {"source": SOURCE_MEASURED, "frames": _frames, "viewports": vps, "passes": passes,
		"basis": "per viewport and per pass measured; materials are an estimate (est_gpu_ms)"}


## Adds [code]est_gpu_ms[/code] to each material row of [param rows] (the draw table): [param gpu_ms] shared by est_draws.
## A labelled estimate, not a timer: the engine has no per-material GPU time.
static func apportion(rows: Array, gpu_ms: float) -> void:
	var total := 0.0
	for r: Dictionary in rows:
		if r.get("kind", "") == "material":
			total += float(r.get("est_draws", 0))
	if total <= 0.0 or gpu_ms <= 0.0:
		return
	for r: Dictionary in rows:
		if r.get("kind", "") == "material":
			r["est_gpu_ms"] = gpu_ms * float(r.get("est_draws", 0)) / total
