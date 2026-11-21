extends Node

## The perf report v1: budget ids and addon owners, per-class network cost, loads, a live recording that writes
## perf-<stamp>.json, GPU time (measured passes, the labelled fallback), the call-trace artifacts, the Nightly uploader and an
## open-ended capture, and that file against the required keys (and the schema when tools/perf_report_check.py runs).

const SECTIONS := 11
const CHECKS := 73
const DIR := "user://profiler_perf_selftest"

var _sections := 0
var _checks := 0
var _failed := 0


func _ready() -> void:
	var _r := GSPaths.remove_tree(DIR)
	_budget()
	_net()
	_loads()
	_signals()
	_baseline()
	_caps()
	await _live()
	_gpu()
	_trace()
	_upload()
	await _open_ended()
	var _c := GSPaths.remove_tree(DIR)
	print("profiler_perf_selftest: %d of %d sections, %d checks (want %d), %d failed" % [_sections, SECTIONS, _checks, CHECKS, _failed])
	get_tree().quit(0 if _failed == 0 and _sections == SECTIONS and _checks == CHECKS else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)


func _budget() -> void:
	GSProfilerBudget.clear_owners()
	_check(GSProfilerBudget.id_for("frame", 0) == "frame" and GSProfilerBudget.id_for("physics", 1) == "engine.physics"
		and GSProfilerBudget.id_for("scripts", 2) == "engine.scripts" and GSProfilerBudget.id_for("physics", 3) == "physics", "engine phases get engine.* ids only near the root")
	_check(GSProfilerBudget.owner_of("fc.bots") == "fc" and GSProfilerBudget.owner_of("engine.render") == "engine" and GSProfilerBudget.owner_of("solo") == "solo", "the owner is the first dotted segment")
	GSProfilerBudget.register_owner("fc.net", "dot-net")
	GSProfilerBudget.register_owner("fc", "fatal-contact")
	_check(GSProfilerBudget.owner_of("fc.net_recv") == "dot-net" and GSProfilerBudget.owner_of("fc.bots") == "fatal-contact", "the longest registered prefix owns an id")
	var tree := [
		{"path": "frame", "name": "frame", "depth": 0, "ms": 10.0, "self_ms": 0.0, "calls": 1.0, "p95_ms": 12.0, "max_ms": 20.0},
		{"path": "frame;process", "name": "process", "depth": 1, "ms": 6.0, "self_ms": 1.0, "calls": 1.0, "p95_ms": 7.0, "max_ms": 9.0},
		{"path": "frame;process;fc.bots", "name": "fc.bots", "depth": 2, "ms": 5.0, "self_ms": 5.0, "calls": 2.0, "p95_ms": 6.0, "max_ms": 8.0}]
	var rows := GSProfilerBudget.rows(tree, 10.0, 16.0, 0)
	_check(rows.size() == 3 and rows[0].id == "frame" and rows[1].id == "engine.process" and rows[2].parent == "engine.process" and rows[2].addon == "fatal-contact", "rows carry id, parent and addon")
	_check(is_equal_approx(rows[2].pct_frame, 50.0) and is_equal_approx(rows[2].pct_budget, 5.0 / 16.0 * 100.0), "rows carry the share of frame and budget")
	_check(GSProfilerBudget.rows(tree, 10.0, 16.0, 2).size() == 2, "top limits the rows; 0 keeps all")
	var add := GSProfilerBudget.addons(rows, 10.0, 0)
	_check(add.size() == 2 and add[0].addon == "fatal-contact" and is_equal_approx(add[0].ms_per_frame, 5.0), "addon totals use self time")
	GSProfilerBudget.clear_owners()
	_sections += 1


func _net() -> void:
	GSProfilerNetCost.add(&"snap", GSProfilerNetCost.OUT, 100)
	_check(GSProfilerNetCost.rows(1.0).is_empty(), "net cost counts nothing while off")
	GSProfilerNetCost.begin()
	GSProfilerNetCost.add(&"snap", GSProfilerNetCost.OUT, 100)
	GSProfilerNetCost.add(&"snap", GSProfilerNetCost.OUT, 300)
	GSProfilerNetCost.add(&"input", GSProfilerNetCost.IN, 20)
	var rows := GSProfilerNetCost.end(2.0)
	_check(rows.size() == 2 and rows[0].class == "snap" and rows[0].dir == "out" and rows[0].bytes == 400 and rows[0].messages == 2
		and rows[0].max_bytes == 300 and is_equal_approx(rows[0].bytes_per_s, 200.0) and rows[1].dir == "in", "net cost sums bytes, messages and the largest message per class and direction")
	_check(GSProfilerNetCost.rows(2.0, 1).size() == 1, "net cost top limits rows")
	_sections += 1


func _loads() -> void:
	GSProfilerLoads.add("x", &"scene", 0)
	GSProfilerLoads.begin(0.0)
	var t := GSProfilerLoads.now()
	OS.delay_msec(3)
	GSProfilerLoads.add("res://a.tscn", &"scene", t)
	GSProfilerLoads.begin(10000.0)
	GSProfilerLoads.add("res://fast.tscn", &"scene", GSProfilerLoads.now())
	_check(GSProfilerLoads.end().is_empty(), "a load under the floor is dropped")
	GSProfilerLoads.begin(0.0)
	GSProfilerLoads.add("res://a.tscn", &"scene", GSProfilerLoads.now() - 3000)
	var rows := GSProfilerLoads.end()
	_check(rows.size() == 1 and rows[0].name == "res://a.tscn" and rows[0].ms >= 3.0 and rows[0].kind == "scene", "a load is recorded with its time")
	_sections += 1


func _live() -> void:
	var cfg := GSProfilerConfig.new()
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
	var prof := GSProfiler.new()
	prof.register_as_service = false
	prof.config = cfg
	add_child(prof)
	prof.set_perf_option("map", "box")
	prof.set_perf_option("bots", 4)
	var _s := prof.start_recording(0.3)
	GSProfilerNetCost.add(&"snap", GSProfilerNetCost.OUT, 64)
	GSProfilerSignals.note(&"sig", 2)
	GSProfilerSignals.note(&"sig", 4)
	var res: GSResult = await prof.recording_finished
	_check(res.ok and prof.last_perf_path() != "", "a recording writes a perf report")
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prof.last_perf_path()))
	_check(GSProfilerPerfReport.problems(p).is_empty(), "the perf report has every required key")
	_check(p.game_id == "selftest-game" and p.role == "client" and p.platform == "native" and p.map == "box" and int(p.bots) == 4, "game id, role, platform and options are written")
	_check(int(p.frame.count) > 0 and p.frame.ms.has("p99") and p.frame.ms.has("max"), "frame percentiles are written")
	_check(p.has("network") and p.network.by_class[0].class == "snap" and p.network.by_class[0].bytes == 64, "network cost per class is written")
	_check(p.has("render") and p.render.has("top_draw") and p.render.top_draw.size() > 0, "the draw scan lists meshes and materials")
	_check(int(p.schema_minor) == 1 and p.render.has("cost_estimate") and p.render.top_draw[0].has("est_cost"), "schema_minor and the labelled render cost estimate are written")
	_check(p.has("budget") and p.budget[0].has("path"), "budget rows carry their path")
	_check(p.has("signals") and p.signals.fanout[0].signal == "sig" and p.signals.fanout[0].deliveries == 6, "signal fan-out is written")
	_check(p.has("budget") and p.has("hitches") and p.has("memory"), "budget, hitches and memory sections exist")
	var bad := GSProfilerPerfReport.problems({"schema": "x"})
	_check(bad.size() >= 5, "a bad report names what is missing")
	_check(FileAccess.file_exists(prof.last_perf_path()) and prof.last_perf_path().get_file().begins_with("perf-"), "the file is named perf-<stamp>.json")
	prof.queue_free()
	mi.queue_free()
	await get_tree().process_frame
	_sections += 1


func _signals() -> void:
	GSProfilerSignals.note(&"a", 3)
	_check(GSProfilerSignals.rows(1.0).is_empty(), "signal counts do nothing while off")
	GSProfilerSignals.begin()
	GSProfilerSignals.note(&"a", 3)
	GSProfilerSignals.note(&"a", 1)
	GSProfilerSignals.note(&"b", 1)
	var rows := GSProfilerSignals.end(2.0)
	_check(rows.size() == 2 and rows[0].signal == "a" and rows[0].emits == 2 and rows[0].deliveries == 4 and rows[0].receivers_max == 3
		and is_equal_approx(rows[0].receivers_avg, 2.0) and is_equal_approx(rows[0].deliveries_per_s, 2.0), "fan-out sums emits, receivers and deliveries")
	_check(GSProfilerSignals.rows(2.0, 1).size() == 1, "signal top limits rows")
	var n := Node.new()
	n.add_user_signal("hit")
	n.connect("hit", func() -> void: pass)
	n.connect("hit", func() -> void: pass)
	GSProfilerSignals.begin()
	GSProfilerSignals.emitted(n, &"hit")
	var r2 := GSProfilerSignals.end(1.0)
	_check(r2.size() == 1 and r2[0].receivers_max == 2 and r2[0].signal == "Node.hit", "emitted reads the connection count")
	n.free()
	_sections += 1


func _baseline() -> void:
	var ref := {"made_utc": "t0", "build": {"commit": "aaa"}, "frame": {"ms": {"avg": 10.0, "p99": 20.0}, "fps_avg": 100.0},
		"budget": [{"id": "fc.bots", "ms_per_frame": 2.0}], "network": {"by_class": [{"class": "snap", "dir": "out", "bytes_per_s": 1000.0}]}}
	var cur := {"frame": {"ms": {"avg": 12.0, "p99": 20.2}, "fps_avg": 90.0}, "budget": [{"id": "fc.bots", "ms_per_frame": 1.0}],
		"network": {"by_class": [{"class": "snap", "dir": "out", "bytes_per_s": 1000.0}]}}
	var d := GSProfilerPerfBaseline.diff(cur, ref, 5.0, "ref.json")
	var keys := []
	for c: Dictionary in d.changed:
		keys.append(c.key)
	_check(d.against == "ref.json" and d.against_commit == "aaa" and d.noise_pct == 5.0 and not keys.has("frame.ms.p99") and not keys.has("net.snap.out"), "rows inside the noise floor are dropped")
	_check(keys.has("frame.ms.avg") and keys.has("frame.fps_avg") and keys.has("budget.fc.bots") and d.worse == 2 and d.better == 1, "rows beyond the noise floor are listed with a direction (fps down is worse)")
	_check(GSProfilerPerfBaseline.diff(cur, ref, 0.0, "x").changed.size() == 4, "noise 0 lists every difference")
	_check(not GSProfilerPerfBaseline.load_report("user://nope.json").ok, "a missing baseline fails loudly")
	_sections += 1


func _caps() -> void:
	var cfg := GSProfilerConfig.new()
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


func _gpu() -> void:
	var g := GSProfilerGpuTime.new()
	var none := g.report(5)
	_check(none.source == "unavailable" and none.has("why") and none.basis == "estimate", "no samples reports unavailable with a reason and the estimate basis")
	g.add_viewport("root", 4.0, 1.0)
	g.add_viewport("root", 2.0, 3.0)
	g.add_viewport("minimap", 0.5, 0.1)
	g.add_pass("opaque", 3.0)
	g.add_pass("opaque", 5.0)
	g.add_pass("shadows", 1.0)
	var r := g.report(0)
	_check(r.source == "measured" and r.viewports[0].name == "root" and is_equal_approx(r.viewports[0].gpu_ms, 2.0) and is_equal_approx(r.viewports[0].cpu_ms, 4.0 / 3.0), "viewport GPU ms is averaged and sorted")
	_check(r.passes[0].name == "opaque" and is_equal_approx(r.passes[0].avg_ms, 4.0) and is_equal_approx(r.passes[0].max_ms, 5.0) and int(r.passes[0].frames) == 2, "pass avg, max and frames")
	_check(g.report(1).passes.size() == 1 and g.report(1).viewports.size() == 1 and g.report(0).passes.size() == 2, "top caps the rows and 0 keeps every row")
	var rows: Array = [{"kind": "material", "name": "a", "est_draws": 3}, {"kind": "material", "name": "b", "est_draws": 1}, {"kind": "mesh", "name": "m", "est_draws": 9}]
	GSProfilerGpuTime.apportion(rows, 8.0)
	_check(is_equal_approx(rows[0].est_gpu_ms, 6.0) and is_equal_approx(rows[1].est_gpu_ms, 2.0) and not rows[2].has("est_gpu_ms"), "material GPU ms is a share of the frame by draws, meshes get none")
	var out := GSProfilerPerfReport._render({"render_gpu_ms": {"avg": 8.0}}, {"gpu_time": r, "render_top": [{"kind": "material", "name": "a", "est_draws": 1}]})
	_check(out.gpu.source == "measured" and is_equal_approx(out.top_draw[0].est_gpu_ms, 8.0), "render.gpu carries the numbers and materials get est_gpu_ms")
	var out2 := GSProfilerPerfReport._render({}, {"gpu_time": none, "render_top": [{"kind": "material", "name": "a", "est_draws": 1}]})
	_check(out2.gpu.source == "unavailable" and not out2.top_draw[0].has("est_gpu_ms"), "unavailable GPU time keeps the labelled estimate only")
	_sections += 1


const FOLDED := "frame;physics;fc.a 600\nframe;physics;fc.b 200\nframe;scripts;fc.c 150\nframe;render 50\n"


func _trace() -> void:
	var root := GSProfilerTraceArt.parse(FOLDED)
	_check(is_equal_approx(root.v, 1000.0) and root.kids.has("frame") and is_equal_approx(root.kids.frame.v, 1000.0), "folded stacks parse into a tree with totals")
	_check(GSProfilerTraceArt.parse("").v == 0.0 and GSProfilerTraceArt.svg("", "t") == "" and GSProfilerTraceArt.thumbnail("") == null, "empty stacks draw nothing")
	var all := GSProfilerTraceArt.boxes(root, 0)
	_check(all.size() == 8, "0 keeps every box (got %d)" % all.size())
	var capped := GSProfilerTraceArt.boxes(root, 3)
	var names := capped.map(func(b: Dictionary) -> String: return b.name)
	_check(capped.size() == 3 and names.has("all") and names.has("frame") and names.has("physics"), "a cap keeps the widest boxes, parents with them")
	var svg := GSProfilerTraceArt.svg(FOLDED, "a <b> & c", 600, 0)
	_check(svg.begins_with("<svg") and svg.contains("fc.a") and svg.contains("a &lt;b&gt; &amp; c") and not svg.contains("<b>"), "the SVG names the calls and escapes the title")
	var page := GSProfilerTraceArt.html(FOLDED, "t", 600, 0)
	_check(page.begins_with("<!doctype html>") and page.contains("</svg>"), "the HTML page holds the SVG")
	var img := GSProfilerTraceArt.thumbnail(FOLDED, 200, 6, 0)
	_check(img != null and img.get_width() == 200 and img.get_height() == 4 * 6, "the thumbnail is as wide as asked and one row per depth")
	var base := DIR.path_join("trace_case")
	var w := GSProfilerTraceArt.write(FOLDED, base, "t", 120, 0)
	_check(w.ok and FileAccess.file_exists(base + ".trace.html") and FileAccess.file_exists(base + ".trace.png"), "write makes the .trace.html and .trace.png")
	var png := Image.load_from_file(base + ".trace.png")
	_check(png != null and png.get_width() == 120, "the PNG loads back at the configured width")
	var small := GSProfilerTraceArt.svg(FOLDED, "t", 600, 3)
	_check(small.length() < svg.length(), "a box cap makes the file smaller")
	var w2 := GSProfilerTraceArt.write(FOLDED, DIR.path_join("no_png"), "t", 0, 0)
	_check(w2.ok and not FileAccess.file_exists(DIR.path_join("no_png.trace.png")), "png width 0 writes the page only")
	_check(GSProfilerTraceArt.write("", DIR.path_join("empty"), "t", 120, 0).value == "", "no stacks writes nothing and is not an error")
	_sections += 1


func _upload() -> void:
	var perf := {"game_id": "g", "platform": "web", "role": "client", "map": "de dust", "build": {"commit": "abc"}}
	var url := GSProfilerUpload.url_for("https://n.example/", perf)
	_check(url == "https://n.example/api/perf/ingest?game=g&platform=web&role=client&map=de%20dust&commit=abc", "the ingest URL carries the scope as query (got %s)" % url)
	_check(GSProfilerUpload.url_for("https://n.example/api/perf/ingest", perf).count("/api/perf/ingest") == 1, "a full ingest URL is not doubled")
	var req := GSProfilerUpload.request("https://n.example", perf, "frame;a 5", "nps_SECRET")
	var env: Dictionary = JSON.parse_string(req.body)
	_check(env.report.game_id == "g" and env.folded == "frame;a 5", "the body is the {report, folded} envelope")
	_check(not req.url.contains("SECRET") and not req.body.contains("SECRET") and "Authorization: Bearer nps_SECRET" in req.headers, "the token is only in the Authorization header")
	_check(not "Authorization: Bearer " in GSProfilerUpload.request("https://n.example", perf, "", "").headers, "no token sends no Authorization header")
	var tf := DIR.path_join("token")
	var f := FileAccess.open(tf, FileAccess.WRITE)
	f.store_string("nps_FILE\nsecond line\n")
	f.close()
	if OS.get_environment(GSProfilerUpload.TOKEN_ENV) == "":
		_check(GSProfilerUpload.token(tf) == "nps_FILE" and GSProfilerUpload.token("") == "" and GSProfilerUpload.token("user://missing") == "", "the token file's first line is the token")
	else:
		_check(GSProfilerUpload.token(tf) == OS.get_environment(GSProfilerUpload.TOKEN_ENV).strip_edges(), "the environment token wins over the file")
	var cfg := GSProfilerConfig.new()
	_check(cfg.perf_upload_url == "" and cfg.perf_trace and cfg.perf_gpu_time and cfg.perf_trace_max_boxes == 2000, "upload is off by default, trace and GPU time on")
	cfg.perf_upload_url = "ftp://x"
	_check(not cfg.validate().ok, "an upload URL must be http or https")
	cfg.perf_upload_url = "https://n.example"
	cfg.perf_trace_max_boxes = -1
	_check(not cfg.validate().ok, "a negative box cap fails loudly")
	cfg.perf_trace_max_boxes = 0
	cfg.capture_seconds = -2.0
	_check(not cfg.validate().ok, "a negative capture_seconds fails loudly")
	cfg.capture_seconds = 0.0
	_check(cfg.validate().ok, "capture_seconds 0 (open-ended) and 0 boxes (unlimited) are valid")
	_sections += 1


func _open_ended() -> void:
	var cfg := GSProfilerConfig.new()
	cfg.record_dir = DIR
	cfg.sample_hz = 0.0
	cfg.perf_upload_url = "http://127.0.0.1:1"
	var prof := GSProfiler.new()
	prof.register_as_service = false
	prof.config = cfg
	add_child(prof)
	var bad := prof.start_recording(-1.0)
	_check(not bad.ok and not prof.is_recording(), "a negative length fails loudly and starts nothing")
	var started := prof.start_recording(0.0, true)
	_check(started.ok and prof.is_open_ended() and prof.recording_length_s() == 0.0, "an open-ended recording starts with no length")
	await get_tree().create_timer(0.6).timeout
	_check(prof.is_recording(), "it is still running after 0.6 s (no auto stop)")
	var ended: Array = []
	prof.perf_uploaded.connect(func(ok: bool, status: int, message: String) -> void: ended.append([ok, status, message]))
	var res := prof.stop_recording()
	_check(res.ok and not prof.is_recording() and not prof.is_open_ended(), "stop_recording ends it and writes")
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(res.value))
	_check(float(rep.seconds) >= 0.5, "the report's seconds is the real length (%s)" % rep.get("seconds"))
	var t := 0.0
	while ended.is_empty() and t < 10.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	_check(not ended.is_empty() and ended[0][0] == false and not str(ended[0][2]).contains("nps_"), "an upload to a closed port reports failure through perf_uploaded")
	prof.queue_free()
	await get_tree().process_frame
	_sections += 1
