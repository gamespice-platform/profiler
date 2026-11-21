#!/usr/bin/env python3
"""Checks perf report JSON files against docs/perf-report.schema.json (stdlib only; the subset of draft 2020-12 the
schema uses: type, required, enum, properties, items, $ref into $defs, minimum, const).

    python3 tools/perf_report_check.py perf-*.json      exit 0 when every file is valid
"""
import json
import os
import sys

SCHEMA_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "perf-report.schema.json")
TYPES = {"object": dict, "array": list, "string": str, "boolean": bool, "null": type(None)}


def _is(value, t):
    if t == "integer":
        return isinstance(value, int) and not isinstance(value, bool) or (isinstance(value, float) and value.is_integer())
    if t == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, TYPES[t])


def check(value, schema, root, path="$"):
    """Problems of [value] against [schema] as a list of "path: message"."""
    out = []
    if "$ref" in schema:
        ref = schema["$ref"]
        if not ref.startswith("#/$defs/"):
            return ["%s: unsupported $ref %s" % (path, ref)]
        return check(value, root["$defs"][ref[len("#/$defs/"):]], root, path)
    t = schema.get("type")
    if t is not None:
        types = t if isinstance(t, list) else [t]
        if not any(_is(value, x) for x in types):
            return ["%s: expected %s, got %s" % (path, "|".join(types), type(value).__name__)]
    if "const" in schema and value != schema["const"]:
        out.append("%s: must be %r" % (path, schema["const"]))
    if "enum" in schema and value not in schema["enum"]:
        out.append("%s: %r not in %s" % (path, value, schema["enum"]))
    if "minimum" in schema and isinstance(value, (int, float)) and value < schema["minimum"]:
        out.append("%s: %r below %r" % (path, value, schema["minimum"]))
    if isinstance(value, dict):
        for k in schema.get("required", []):
            if k not in value:
                out.append("%s: missing %s" % (path, k))
        for k, sub in schema.get("properties", {}).items():
            if k in value:
                out += check(value[k], sub, root, "%s.%s" % (path, k))
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            out += check(item, schema["items"], root, "%s[%d]" % (path, i))
    return out


def validate(report):
    with open(SCHEMA_PATH) as f:
        schema = json.load(f)
    return check(report, schema, schema)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    bad = 0
    for p in argv:
        with open(p) as f:
            problems = validate(json.load(f))
        print("%s: %s" % (p, "ok" if not problems else "%d problem(s)" % len(problems)))
        for m in problems[:20]:
            print("  " + m)
        bad += bool(problems)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
