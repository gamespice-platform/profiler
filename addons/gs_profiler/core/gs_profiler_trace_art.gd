class_name GSProfilerTraceArt
extends RefCounted

## A viewable call trace for one recording, from its folded stacks: a self-contained HTML page with an SVG icicle graph (width = time, hover for name and share) and a PNG thumbnail.
## Both land beside the perf report as [code]perf-<stamp>.trace.html[/code] and [code].trace.png[/code]; Nightly renders its own from the uploaded stacks. [param max_boxes] caps size (widest boxes win; 0 keeps all).

const ROW_H := 16
const MIN_LABEL_PX := 44.0


## Parses folded stacks ("a;b;c 12" per line) into {name, v, kids: [..]} (the root is "all").
static func parse(folded: String) -> Dictionary:
	var root := {"name": "all", "v": 0.0, "kids": {}}
	for line in folded.split("\n", false):
		var sp := line.rfind(" ")
		if sp <= 0:
			continue
		var w := line.substr(sp + 1).to_float()
		if w <= 0.0:
			continue
		root.v += w
		var node := root
		for part in line.substr(0, sp).split(";", false):
			var kids: Dictionary = node.kids
			if not kids.has(part):
				kids[part] = {"name": part, "v": 0.0, "kids": {}}
			node = kids[part]
			node.v += w
	return root


## Lays the tree out in [0, 1] and returns [{name, x, w, depth, v}] (x and w are fractions of the width).
## [param max_boxes] 0 keeps every box.
static func boxes(root: Dictionary, max_boxes: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var total: float = root.v
	if total <= 0.0:
		return out
	var stack: Array = [[root, 0.0, 0]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Dictionary = it[0]
		var x: float = it[1]
		out.append({"name": node.name, "x": x, "w": float(node.v) / total, "depth": it[2], "v": node.v})
		var kids: Array = (node.kids as Dictionary).values()
		kids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.v > b.v)
		var cx := x
		for k: Dictionary in kids:
			stack.append([k, cx, int(it[2]) + 1])
			cx += float(k.v) / total
	if max_boxes > 0 and out.size() > max_boxes:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.w > b.w if a.w != b.w else a.depth < b.depth)
		out.resize(max_boxes)
	return out


static func _color(name: String) -> Color:
	var h := float(name.hash() % 360) / 360.0
	return Color.from_hsv(h, 0.45, 0.92)


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


## The SVG graph of [param folded], [param width] px wide. "" when the folded stacks are empty.
static func svg(folded: String, title: String, width: int = 1200, max_boxes: int = 0) -> String:
	var root := parse(folded)
	var bx := boxes(root, max_boxes)
	if bx.is_empty():
		return ""
	var depth := 0
	for b: Dictionary in bx:
		depth = maxi(depth, int(b.depth))
	var h := (depth + 1) * ROW_H + 24
	var s := PackedStringArray()
	s.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" font-family=\"monospace\" font-size=\"11\">" % [width, h, width, h])
	s.append("<rect width=\"100%%\" height=\"100%%\" fill=\"#fafafa\"/><text x=\"4\" y=\"14\" font-size=\"12\">%s</text>" % _esc(title))
	var total: float = root.v
	for b: Dictionary in bx:
		var px := float(b.x) * width
		var pw := maxf(float(b.w) * width, 0.5)
		var y := 20 + int(b.depth) * ROW_H
		s.append("<g><title>%s: %s (%.1f%%)</title><rect x=\"%.1f\" y=\"%d\" width=\"%.1f\" height=\"%d\" fill=\"#%s\" stroke=\"#fff\" stroke-width=\"0.5\"/>" % [
			_esc(b.name), _fmt(b.v), float(b.v) / total * 100.0, px, y, pw, ROW_H - 1, _color(b.name).to_html(false)])
		if pw >= MIN_LABEL_PX:
			var chars := int((pw - 4.0) / 6.5)
			var label: String = b.name if b.name.length() <= chars else b.name.left(maxi(chars - 1, 1)) + "~"
			s.append("<text x=\"%.1f\" y=\"%d\" fill=\"#222\">%s</text>" % [px + 3.0, y + 11, _esc(label)])
		s.append("</g>")
	s.append("</svg>")
	return "\n".join(s)


static func _fmt(v: float) -> String:
	return "%.2f ms" % (v / 1000.0) if v >= 1000.0 else "%d us" % int(v)


## A self-contained HTML page holding [method svg]. "" when there is nothing to draw.
static func html(folded: String, title: String, width: int = 1200, max_boxes: int = 0) -> String:
	var g := svg(folded, title, width, max_boxes)
	if g == "":
		return ""
	return "<!doctype html><html><head><meta charset=\"utf-8\"><title>%s</title></head><body style=\"margin:8px;background:#fafafa\">\n%s\n<p style=\"font:12px sans-serif;color:#555\">Call trace: width is time under each call (folded stacks, widest boxes first). Hover a box for its name and share.</p></body></html>\n" % [_esc(title), g]


## The thumbnail PNG layout of [param folded]: [param width] px wide, [param row_px] per depth row; null when empty.
static func thumbnail(folded: String, width: int = 480, row_px: int = 6, max_boxes: int = 0) -> Image:
	var bx := boxes(parse(folded), max_boxes)
	if bx.is_empty():
		return null
	var depth := 0
	for b: Dictionary in bx:
		depth = maxi(depth, int(b.depth))
	var img := Image.create_empty(width, (depth + 1) * row_px, false, Image.FORMAT_RGB8)
	img.fill(Color("fafafa"))
	for b: Dictionary in bx:
		var x := int(float(b.x) * width)
		var w := maxi(int(float(b.w) * width), 1)
		img.fill_rect(Rect2i(x, int(b.depth) * row_px, w, row_px - 1), _color(b.name))
	return img


## Writes [code]<base>.trace.html[/code] (and [code].trace.png[/code] when [param png_width] is above 0) for [param folded].
## The value is the HTML path; "" (still ok) when there is nothing to draw.
static func write(folded: String, base: String, title: String, png_width: int, max_boxes: int) -> GSResult:
	var page := html(folded, title, 1200, max_boxes)
	if page == "":
		return GSResult.success("")
	var w := GSPaths.write_text(base + ".trace.html", page)
	if not w.ok:
		return w.wrap("profiler: cannot write the call trace")
	if png_width > 0:
		var img := thumbnail(folded, png_width, 6, max_boxes)
		if img != null and img.save_png(base + ".trace.png") != OK:
			return GSResult.fail(GSError.CODE_IO, "Cannot write %s." % (base + ".trace.png"))
	return GSResult.success(base + ".trace.html")
