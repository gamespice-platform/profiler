#!/usr/bin/env python3
"""Uploads a perf report (and its folded stacks) to Nightly's /api/perf/ingest: the CLI twin of DotProfilerUpload.

    NIGHTLY_PERF_TOKEN=nps_... python3 tools/perf_upload.py perf-2026....json --url https://nightly.example
    python3 tools/perf_upload.py perf.json --folded rec.folded --token-file ~/.config/nightly/perf-token --url ...

The token comes from the environment variable NIGHTLY_PERF_TOKEN or the first line of --token-file; it is never an
argument (argv shows in process lists) and is never printed. Exit 0 on a 2xx answer, 1 otherwise.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN_ENV = "NIGHTLY_PERF_TOKEN"
INGEST = "/api/perf/ingest"


def read_token(token_file=""):
    t = os.environ.get(TOKEN_ENV, "").strip()
    if t or not token_file:
        return t
    try:
        with open(os.path.expanduser(token_file), encoding="utf-8") as f:
            return f.readline().strip()
    except OSError:
        return ""


def ingest_url(base, perf):
    u = base.strip().rstrip("/")
    if not u.endswith(INGEST):
        u += INGEST
    q = {"game": perf.get("game_id", ""), "platform": perf.get("platform", ""), "role": perf.get("role", ""),
         "map": perf.get("map", ""), "bots": perf.get("bots", ""), "commit": (perf.get("build") or {}).get("commit", ""),
         "gpu": perf.get("gpu", "")}
    q = {k: str(v) for k, v in q.items() if str(v) not in ("", "unknown")}
    return u + ("?" + urllib.parse.urlencode(q) if q else "")


def build_request(base, perf, folded, token):
    body = {"report": perf}
    if folded:
        body["folded"] = folded
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    return urllib.request.Request(ingest_url(base, perf), data=json.dumps(body).encode(), headers=headers, method="POST")


def upload(base, report_path, folded_path="", token_file="", timeout=30):
    """Returns (ok, status, message); the message never holds the token."""
    with open(report_path, encoding="utf-8") as f:
        perf = json.load(f)
    folded = ""
    if folded_path:
        with open(folded_path, encoding="utf-8") as f:
            folded = f.read()
    req = build_request(base, perf, folded, read_token(token_file))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return 200 <= r.status < 300, r.status, "HTTP %d" % r.status
    except urllib.error.HTTPError as e:
        return False, e.code, "HTTP %d: %s" % (e.code, e.read(200).decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError) as e:
        return False, 0, "request failed: %s" % getattr(e, "reason", e)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("report", help="perf-<stamp>.json")
    ap.add_argument("--url", required=True, help="Nightly base URL or the full /api/perf/ingest URL")
    ap.add_argument("--folded", default="", help="folded stacks file (the recording's .folded)")
    ap.add_argument("--token-file", default="", help="file whose first line is the token (else $%s)" % TOKEN_ENV)
    a = ap.parse_args(argv)
    if not read_token(a.token_file):
        print("perf_upload: no token (set %s or --token-file); sending without one" % TOKEN_ENV, file=sys.stderr)
    ok, status, msg = upload(a.url, a.report, a.folded, a.token_file)
    print(("uploaded: " if ok else "upload failed: ") + msg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
