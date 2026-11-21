class_name DotProfilerCensus
extends RefCounted
## Node counts by class, and the difference between two counts (DotProfiler.census / census_diff delegate here).


## Nodes under [param root] by class (a script's class_name when it has one): {name: count}.
static func count(root: Node) -> Dictionary:
	var out := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key := n.get_class()
		var sc := n.get_script() as Script
		if sc != null and sc.get_global_name() != &"":
			key = String(sc.get_global_name())
		out[key] = int(out.get(key, 0)) + 1
		stack.append_array(n.get_children(true))
	return out


## Two [method count] results as {start_nodes, end_nodes, classes: [{class, start, end, delta}]}, biggest change first.
static func diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var rows: Array = []
	var total_a := 0
	var total_b := 0
	var names := a.keys()
	for k: Variant in b:
		if not a.has(k):
			names.append(k)
	for k: Variant in names:
		var x: int = a.get(k, 0)
		var y: int = b.get(k, 0)
		total_a += x
		total_b += y
		rows.append({"class": String(k), "start": x, "end": y, "delta": y - x})
	rows.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return absi(p.delta) > absi(q.delta) or (p.delta == q.delta and p.end > q.end))
	return {"start_nodes": total_a, "end_nodes": total_b, "classes": rows}
