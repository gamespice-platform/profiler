#!/usr/bin/env python3
"""Checks perf_report_check.py against the schema: python3 tools/perf_report_check_test.py"""
import copy
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_report_check as pc  # noqa: E402

OK = {"schema": "gamespice.perf-report", "schema_version": 1, "game_id": "g", "build": {"commit": "abc"}, "platform": "web",
      "role": "client", "scene": "res://a.tscn", "duration_s": 10.0, "frame": {"count": 100, "ms": {"avg": 5.0, "max": 9.0, "p99": 8.0}},
      "budget": [{"id": "fc.bots", "ms_per_frame": 1.0}], "hitches": [{"t": 1.0, "ms": 40.0, "cause": "fc.bots"}]}


class CheckTest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(pc.validate(OK), [])

    def test_missing_and_bad(self):
        r = copy.deepcopy(OK)
        del r["game_id"]
        r["platform"] = "mobile"
        r["budget"][0]["ms_per_frame"] = "x"
        r["frame"]["ms"].pop("avg")
        got = "\n".join(pc.validate(r))
        for want in ("missing game_id", "platform", "budget[0].ms_per_frame", "missing avg"):
            self.assertIn(want, got)


if __name__ == "__main__":
    unittest.main()
