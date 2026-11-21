class_name DotProfilerSignals
extends RefCounted

## Signal fan-out for the perf report's [code]signals.fanout[/code]: how often a signal fires and how many receivers each emit reaches. The emitter says so:
## [code]DotProfilerSignals.emitted(self, &"health_changed")[/code] right before (or after) [code]emit_signal[/code]; or [code]note(&"name", receivers)[/code] when it already knows the count.
## Emit count times receivers (deliveries) is what a hot signal costs.
##
## Main thread only. One bool test while no recording runs; after a signal's first emit an add allocates nothing.

## True while a recording runs; the helpers do nothing otherwise.
static var enabled: bool = false

## Per signal name: an Array (a reference, so adds change it in place) [emits, deliveries, max_receivers].
static var _signals: Dictionary = {}


## Counts one emit of [param name] that reaches [param receivers] callables.
static func note(name: StringName, receivers: int) -> void:
	if not enabled:
		return
	var row: Array = _signals.get(name, [])
	if row.is_empty():
		row = [0, 0, 0]
		_signals[name] = row
	row[0] += 1
	row[1] += receivers
	if receivers > row[2]:
		row[2] = receivers


## Counts one emit of [param signal_name] on [param obj], reading its current connection count.
static func emitted(obj: Object, signal_name: StringName) -> void:
	if not enabled:
		return
	note(StringName("%s.%s" % [obj.get_class(), signal_name]), obj.get_signal_connection_list(signal_name).size())


## Starts counting from zero.
static func begin() -> void:
	_signals = {}
	enabled = true


## Stops counting and returns [method rows] over [param seconds].
static func end(seconds: float, top: int = 0) -> Array:
	enabled = false
	return rows(seconds, top)


## [{signal, emits, receivers_max, receivers_avg, deliveries, deliveries_per_s}], most deliveries first; [param top] 0 keeps all.
static func rows(seconds: float, top: int = 0) -> Array:
	var out: Array = []
	var s := maxf(seconds, 0.001)
	for name: StringName in _signals:
		var row: Array = _signals[name]
		out.append({"signal": String(name), "emits": row[0], "receivers_max": row[2], "receivers_avg": float(row[1]) / row[0],
			"deliveries": row[1], "deliveries_per_s": row[1] / s})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.deliveries > b.deliveries)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out
