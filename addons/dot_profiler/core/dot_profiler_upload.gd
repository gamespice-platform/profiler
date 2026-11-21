class_name DotProfilerUpload
extends RefCounted

## Posts a finished perf report (v1 / v1.1) and its folded stacks to Nightly's `/api/perf/ingest` (docs/perf-report.md,
## "Uploading"). Off unless [member DotProfilerConfig.perf_upload_url] is set. The Bearer token comes from the environment
## variable [constant TOKEN_ENV] or the first line of [member DotProfilerConfig.perf_upload_token_file]; it has no cvar and
## no command-line form (argv shows in process lists), and it is only ever put in the request header, never logged or
## returned in a message. Uses HTTPRequest, so it works in a web export (the panel must allow the page's origin).

const TOKEN_ENV := "NIGHTLY_PERF_TOKEN"
const INGEST_PATH := "/api/perf/ingest"


## The token, or "" when neither the environment nor the file has one.
static func token(token_file: String = "") -> String:
	var t := OS.get_environment(TOKEN_ENV).strip_edges()
	if t != "" or token_file == "":
		return t
	if not FileAccess.file_exists(token_file):
		return ""
	var f := FileAccess.open(token_file, FileAccess.READ)
	if f == null:
		return ""
	return f.get_line().strip_edges()


## The ingest URL for [param base] (a panel root or the full ingest URL) with the report's game and scope as query.
static func url_for(base: String, perf: Dictionary) -> String:
	var u := base.strip_edges().rstrip("/")
	if not u.ends_with(INGEST_PATH):
		u += INGEST_PATH
	var q := PackedStringArray()
	var pairs := [["game", perf.get("game_id", "")], ["platform", perf.get("platform", "")], ["role", perf.get("role", "")],
		["map", perf.get("map", "")], ["bots", perf.get("bots", "")], ["commit", (perf.get("build", {}) as Dictionary).get("commit", "")],
		["gpu", perf.get("gpu", "")]]
	for p: Array in pairs:
		var v := str(p[1])
		if v != "" and v != "unknown":
			q.append("%s=%s" % [p[0], v.uri_encode()])
	return u + ("?" + "&".join(q) if not q.is_empty() else "")


## The request for [param perf] and [param folded]: {url, headers, body}. headers carry the Bearer token when there is one
## (do not print them). The body is the JSON envelope {report, folded} Nightly accepts.
static func request(base: String, perf: Dictionary, folded: String, token_value: String) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token_value != "":
		headers.append("Authorization: Bearer " + token_value)
	var envelope := {"report": perf}
	if folded != "":
		envelope["folded"] = folded
	return {"url": url_for(base, perf), "headers": headers, "body": JSON.stringify(envelope)}


## Sends the request under [param parent] and calls [param done] with (ok: bool, status: int, message: String); the
## message never holds the token. A false [code]ok[/code] is the failure to report (nothing is retried).
## Returns false when the request could not even start.
static func send(parent: Node, req: Dictionary, done: Callable) -> bool:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	parent.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		var msg := "HTTP %d" % code if result == HTTPRequest.RESULT_SUCCESS else "request failed (result %d)" % result
		if not ok and body.size() > 0:
			msg += ": " + body.get_string_from_utf8().left(200)
		http.queue_free()
		done.call(ok, code, msg))
	var err := http.request(req.url, req.headers, HTTPClient.METHOD_POST, req.body)
	if err != OK:
		http.queue_free()
		done.call(false, 0, "request not started (error %d)" % err)
		return false
	return true
