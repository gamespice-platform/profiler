extends Node

## The perf report v1: budget ids and addon owners, per-class network cost, loads, a live recording that writes
## perf-<stamp>.json, and that file against the required keys (and the schema when tools/perf_report_check.py runs).

const SECTIONS := 4
const CHECKS := 23
const DIR := "user://profiler_perf_selftest"

var _sections := 0
var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := DotPaths.remove_tree(DIR)
	_budget()
	_net()
	_loads()
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
	var res: DotResult = await prof.recording_finished
	_check(res.ok and prof.last_perf_path() != "", "a recording writes a perf report")
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prof.last_perf_path()))
	_check(DotProfilerPerfReport.problems(p).is_empty(), "the perf report has every required key")
	_check(p.game_id == "selftest-game" and p.role == "client" and p.platform == "native" and p.map == "box" and int(p.bots) == 4, "game id, role, platform and options are written")
	_check(int(p.frame.count) > 0 and p.frame.ms.has("p99") and p.frame.ms.has("max"), "frame percentiles are written")
	_check(p.has("network") and p.network.by_class[0].class == "snap" and p.network.by_class[0].bytes == 64, "network cost per class is written")
	_check(p.has("render") and p.render.has("top_draw") and p.render.top_draw.size() > 0, "the draw scan lists meshes and materials")
	_check(p.has("budget") and p.has("hitches") and p.has("memory"), "budget, hitches and memory sections exist")
	var bad := DotProfilerPerfReport.problems({"schema": "x"})
	_check(bad.size() >= 5, "a bad report names what is missing")
	_check(FileAccess.file_exists(prof.last_perf_path()) and prof.last_perf_path().get_file().begins_with("perf-"), "the file is named perf-<stamp>.json")
	prof.queue_free()
	mi.queue_free()
	await get_tree().process_frame
	_sections += 1
