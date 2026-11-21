extends Node

## The perf report v1: budget ids and addon owners, per-class network cost, loads, a live recording that writes
## perf-<stamp>.json, and that file against the required keys (and the schema when tools/perf_report_check.py runs).

const SECTIONS := 7
const CHECKS := 37
const DIR := "user://profiler_perf_selftest"

var _sections := 0
var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_budget()
	_net()
	_loads()
	_signals()
	_baseline()
	_caps()
	await _live()
	var _c := DotPaths.remove_tree(DIR)
	print("profiler_perf_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	get_tree().quit(0 if _failed == 0 and _sections == SECTIONS and _checks == CHECKS else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _budget() -> void:
	DotProfilerBudget.clear_owners()
	_check(DotProfilerBudget.id_for("frame", 0) == "frame" and DotProfilerBudget.id_for("physics", 1) == "engine.physics"
		and DotProfilerBudget.id_for("scripts", 2) == "engine.scripts" and DotProfilerBudget.id_for("physics", 3) == "physics", "engine phases get engine.* ids only near the root")
	_check(DotProfilerBudget.owner_of("fc.bots") == "fc" and DotProfilerBudget.owner_of("engine.render") == "engine" and DotProfilerBudget.owner_of("solo") == "solo", "the owner is the first dotted segment")
	DotProfilerBudget.register_owner("fc.net", "dot-net")
	DotProfilerBudget.register_owner("fc", "fatal-contact")
	_check(DotProfilerBudget.owner_of("fc.net_recv") == "dot-net" and DotProfilerBudget.owner_of("fc.bots") == "fatal-contact", "the longest registered prefix owns an id")
	var tree := [
		{"path": "frame", "name": "frame", "depth": 0, "ms": 10.0, "self_ms": 0.0, "calls": 1.0, "p95_ms": 12.0, "max_ms": 20.0},
		{"path": "frame;process", "name": "process", "depth": 1, "ms": 6.0, "self_ms": 1.0, "calls": 1.0, "p95_ms": 7.0, "max_ms": 9.0},
		{"path": "frame;process;fc.bots", "name": "fc.bots", "depth": 2, "ms": 5.0, "self_ms": 5.0, "calls": 2.0, "p95_ms": 6.0, "max_ms": 8.0}]
	var rows := DotProfilerBudget.rows(tree, 10.0, 16.0, 0)
	_check(rows.size() == 3 and rows[0].id == "frame" and rows[1].id == "engine.process" and rows[2].parent == "engine.process" and rows[2].addon == "fatal-contact", "rows carry id, parent and addon")
	_check(is_equal_approx(rows[2].pct_frame, 50.0) and is_equal_approx(rows[2].pct_budget, 5.0 / 16.0 * 100.0), "rows carry the share of frame and budget")
	_check(DotProfilerBudget.rows(tree, 10.0, 16.0, 2).size() == 2, "top limits the rows; 0 keeps all")
	var add := DotProfilerBudget.addons(rows, 10.0, 0)
	_check(add.size() == 2 and add[0].addon == "fatal-contact" and is_equal_approx(add[0].ms_per_frame, 5.0), "addon totals use self time")
	DotProfilerBudget.clear_owners()
	_sections += 1


func _net() -> void:
	DotProfilerNetCost.add(&"snap", DotProfilerNetCost.OUT, 100)
	_check(DotProfilerNetCost.rows(1.0).is_empty(), "net cost counts nothing while off")
	DotProfilerNetCost.begin()
	DotProfilerNetCost.add(&"snap", DotProfilerNetCost.OUT, 100)
	DotProfilerNetCost.add(&"snap", DotProfilerNetCost.OUT, 300)
	DotProfilerNetCost.add(&"input", DotProfilerNetCost.IN, 20)
	var rows := DotProfilerNetCost.end(2.0)
	_check(rows.size() == 2 and rows[0].class == "snap" and rows[0].dir == "out" and rows[0].bytes == 400 and rows[0].messages == 2
		and rows[0].max_bytes == 300 and is_equal_approx(rows[0].bytes_per_s, 200.0) and rows[1].dir == "in", "net cost sums bytes, messages and the largest message per class and direction")
	_check(DotProfilerNetCost.rows(2.0, 1).size() == 1, "net cost top limits rows")
	_sections += 1


func _loads() -> void:
	DotProfilerLoads.add("x", &"scene", 0)
	DotProfilerLoads.begin(0.0)
	var t := DotProfilerLoads.now()
	OS.delay_msec(3)
	DotProfilerLoads.add("res://a.tscn", &"scene", t)
	DotProfilerLoads.begin(10000.0)
	DotProfilerLoads.add("res://fast.tscn", &"scene", DotProfilerLoads.now())
	_check(DotProfilerLoads.end().is_empty(), "a load under the floor is dropped")
	DotProfilerLoads.begin(0.0)
	DotProfilerLoads.add("res://a.tscn", &"scene", DotProfilerLoads.now() - 3000)
	var rows := DotProfilerLoads.end()
	_check(rows.size() == 1 and rows[0].name == "res://a.tscn" and rows[0].ms >= 3.0 and rows[0].kind == "scene", "a load is recorded with its time")
	_sections += 1


func _live() -> void:
	var cfg := DotProfilerConfig.new()
	_check(cfg.perf_report and cfg.perf_top == 25 and cfg.perf_render_scan == false and cfg.validate().ok, "perf options default to the report on and the scan off")
	cfg.perf_role = "bogus"
	_check(not cfg.validate().ok, "a bad perf role fails loudly")
	cfg.perf_role = "client"
	cfg.perf_render_scan = true
	cfg.perf_game_id = "selftest-game"
	cfg.record_dir = DIR
	cfg.sample_hz = 0.0
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = StandardMaterial3D.new()
	add_child(mi)
	var prof := DotProfiler.new()
	prof.register_as_service = false
	prof.config = cfg
	add_child(prof)
	prof.set_perf_option("map", "box")
	prof.set_perf_option("bots", 4)
	var _s := prof.start_recording(0.3)
	DotProfilerNetCost.add(&"snap", DotProfilerNetCost.OUT, 64)
	DotProfilerSignals.note(&"sig", 2)
	DotProfilerSignals.note(&"sig", 4)
	var res: DotResult = await prof.recording_finished
	_check(res.ok and prof.last_perf_path() != "", "a recording writes a perf report")
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prof.last_perf_path()))
	_check(DotProfilerPerfReport.problems(p).is_empty(), "the perf report has every required key")
	_check(p.game_id == "selftest-game" and p.role == "client" and p.platform == "native" and p.map == "box" and int(p.bots) == 4, "game id, role, platform and options are written")
	_check(int(p.frame.count) > 0 and p.frame.ms.has("p99") and p.frame.ms.has("max"), "frame percentiles are written")
	_check(p.has("network") and p.network.by_class[0].class == "snap" and p.network.by_class[0].bytes == 64, "network cost per class is written")
	_check(p.has("render") and p.render.has("top_draw") and p.render.top_draw.size() > 0, "the draw scan lists meshes and materials")
	_check(int(p.schema_minor) == 1 and p.render.has("cost_estimate") and p.render.top_draw[0].has("est_cost"), "schema_minor and the labelled render cost estimate are written")
	_check(p.has("budget") and p.budget[0].has("path"), "budget rows carry their path")
	_check(p.has("signals") and p.signals.fanout[0].signal == "sig" and p.signals.fanout[0].deliveries == 6, "signal fan-out is written")
	_check(p.has("budget") and p.has("hitches") and p.has("memory"), "budget, hitches and memory sections exist")
	var bad := DotProfilerPerfReport.problems({"schema": "x"})
	_check(bad.size() >= 5, "a bad report names what is missing")
	_check(FileAccess.file_exists(prof.last_perf_path()) and prof.last_perf_path().get_file().begins_with("perf-"), "the file is named perf-<stamp>.json")
	prof.queue_free()
	mi.queue_free()
	await get_tree().process_frame
	_sections += 1


func _signals() -> void:
	DotProfilerSignals.note(&"a", 3)
	_check(DotProfilerSignals.rows(1.0).is_empty(), "signal counts do nothing while off")
	DotProfilerSignals.begin()
	DotProfilerSignals.note(&"a", 3)
	DotProfilerSignals.note(&"a", 1)
	DotProfilerSignals.note(&"b", 1)
	var rows := DotProfilerSignals.end(2.0)
	_check(rows.size() == 2 and rows[0].signal == "a" and rows[0].emits == 2 and rows[0].deliveries == 4 and rows[0].receivers_max == 3
		and is_equal_approx(rows[0].receivers_avg, 2.0) and is_equal_approx(rows[0].deliveries_per_s, 2.0), "fan-out sums emits, receivers and deliveries")
	_check(DotProfilerSignals.rows(2.0, 1).size() == 1, "signal top limits rows")
	var n := Node.new()
	n.add_user_signal("hit")
	n.connect("hit", func() -> void: pass)
	n.connect("hit", func() -> void: pass)
	DotProfilerSignals.begin()
	DotProfilerSignals.emitted(n, &"hit")
	var r2 := DotProfilerSignals.end(1.0)
	_check(r2.size() == 1 and r2[0].receivers_max == 2 and r2[0].signal == "Node.hit", "emitted reads the connection count")
	n.free()
	_sections += 1


func _baseline() -> void:
	var ref := {"made_utc": "t0", "build": {"commit": "aaa"}, "frame": {"ms": {"avg": 10.0, "p99": 20.0}, "fps_avg": 100.0},
		"budget": [{"id": "fc.bots", "ms_per_frame": 2.0}], "network": {"by_class": [{"class": "snap", "dir": "out", "bytes_per_s": 1000.0}]}}
	var cur := {"frame": {"ms": {"avg": 12.0, "p99": 20.2}, "fps_avg": 90.0}, "budget": [{"id": "fc.bots", "ms_per_frame": 1.0}],
		"network": {"by_class": [{"class": "snap", "dir": "out", "bytes_per_s": 1000.0}]}}
	var d := DotProfilerPerfBaseline.diff(cur, ref, 5.0, "ref.json")
	var keys := []
	for c: Dictionary in d.changed:
		keys.append(c.key)
	_check(d.against == "ref.json" and d.against_commit == "aaa" and d.noise_pct == 5.0 and not keys.has("frame.ms.p99") and not keys.has("net.snap.out"), "rows inside the noise floor are dropped")
	_check(keys.has("frame.ms.avg") and keys.has("frame.fps_avg") and keys.has("budget.fc.bots") and d.worse == 2 and d.better == 1, "rows beyond the noise floor are listed with a direction (fps down is worse)")
	_check(DotProfilerPerfBaseline.diff(cur, ref, 0.0, "x").changed.size() == 4, "noise 0 lists every difference")
	_check(not DotProfilerPerfBaseline.load_report("user://nope.json").ok, "a missing baseline fails loudly")
	_sections += 1


func _caps() -> void:
	var cfg := DotProfilerConfig.new()
	cfg.sample_hz = 5000.0
	cfg.worst_frames = 100000
	cfg.script_top = 1000000
	cfg.perf_top = 100000
	_check(cfg.validate().ok, "large values are not capped")
	cfg.perf_signal_top = -1
	_check(not cfg.validate().ok, "a negative value fails loudly")
	cfg.perf_signal_top = 0
	cfg.perf_baseline_noise_pct = -1.0
	_check(not cfg.validate().ok, "a negative noise floor fails loudly")
	_sections += 1
