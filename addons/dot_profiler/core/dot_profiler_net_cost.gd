class_name GSProfilerNetCost
extends RefCounted

## Network bytes per message class, reported under the perf report's [code]network.by_class[/code]. The code that
## sends or receives says what a message is: [code]GSProfilerNetCost.add(&"snapshot", GSProfilerNetCost.OUT, packet.size())[/code].
## Source's net_graph and [code]net_showmsg[/code] answer the same question per message.
##
## Main thread only. One bool test while no recording runs; after a class's first message an add allocates nothing.

const IN := 0
const OUT := 1

## True while a recording runs; [method add] does nothing otherwise.
static var enabled: bool = false

## Per class: an Array (a reference, so adds change it in place) [in_bytes, in_msgs, in_max, out_bytes, out_msgs, out_max].
static var _classes: Dictionary = {}


## Counts one message of [param bytes] in direction [param dir] ([constant IN] or [constant OUT]) for [param cls].
static func add(cls: StringName, dir: int, bytes: int) -> void:
	if not enabled:
		return
	var row: Array = _classes.get(cls, [])
	if row.is_empty():
		row = [0, 0, 0, 0, 0, 0]
		_classes[cls] = row
	var o := dir * 3
	row[o] += bytes
	row[o + 1] += 1
	if bytes > row[o + 2]:
		row[o + 2] = bytes


## Starts counting from zero.
static func begin() -> void:
	_classes = {}
	enabled = true


## Stops counting and returns [method rows] over [param seconds].
static func end(seconds: float, top: int = 0) -> Array:
	enabled = false
	return rows(seconds, top)


## [{class, dir "in"|"out", bytes, messages, bytes_per_s, messages_per_s, max_bytes}], biggest first; [param top] 0 keeps all.
static func rows(seconds: float, top: int = 0) -> Array:
	var out: Array = []
	var s := maxf(seconds, 0.001)
	for cls: StringName in _classes:
		var row: Array = _classes[cls]
		for d in 2:
			if row[d * 3 + 1] == 0:
				continue
			out.append({"class": String(cls), "dir": "in" if d == IN else "out", "bytes": row[d * 3], "messages": row[d * 3 + 1],
				"bytes_per_s": row[d * 3] / s, "messages_per_s": row[d * 3 + 1] / s, "max_bytes": row[d * 3 + 2]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.bytes > b.bytes)
	if top > 0 and out.size() > top:
		out.resize(top)
	return out
