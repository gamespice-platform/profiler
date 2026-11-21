class_name GSProfilerLoads
extends RefCounted

## Asset load and stall times for the perf report's [code]loading[/code]: code that loads a scene, resource, map or
## pack says how long it took: [code]var t := GSProfilerLoads.now()[/code] before, then
## [code]GSProfilerLoads.add("res://maps/dust.tscn", &"scene", t)[/code] after. Free while no recording runs.
##
## Main thread only.

static var enabled: bool = false

## Loads shorter than this many ms are dropped; 0 keeps every one.
static var min_ms: float = 0.0

static var _rows: Array = []
static var _t0: int = 0


## A timestamp for [method add].
static func now() -> int:
	return Time.get_ticks_usec() if enabled else 0


## Records a load of [param what] of [param kind] that started at [param started] (from [method now]).
static func add(what: String, kind: StringName, started: int) -> void:
	if not enabled:
		return
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	if ms >= min_ms:
		_rows.append({"name": what, "kind": String(kind), "ms": ms, "t": (started - _t0) / 1000000.0})


## Starts recording loads at least [param floor_ms] long.
static func begin(floor_ms: float = 0.0) -> void:
	_rows = []
	min_ms = floor_ms
	_t0 = Time.get_ticks_usec()
	enabled = true


## Stops and returns [{name, kind, ms, t}], slowest first; [param top] 0 keeps all.
static func end(top: int = 0) -> Array:
	enabled = false
	var out := _rows.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ms > b.ms)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out
