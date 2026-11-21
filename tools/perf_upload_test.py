#!/usr/bin/env python3
"""Checks perf_upload.py against a local server: python3 tools/perf_upload_test.py"""
import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import perf_upload as pu  # noqa: E402

SECRET = "nps_secret_value_123"
PERF = {"game_id": "g", "platform": "native", "role": "client", "map": "dust", "build": {"commit": "abc"}}
seen = {}


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        seen["path"] = self.path
        seen["auth"] = self.headers.get("Authorization", "")
        seen["body"] = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        code = 401 if seen["auth"] != "Bearer " + SECRET else 200
        self.send_response(code)
        self.end_headers()
        self.wfile.write(b"{}")

    def log_message(self, *a):
        pass


class UploadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = HTTPServer(("127.0.0.1", 0), H)
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_port
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.rep = os.path.join(self.d.name, "p.json")
        with open(self.rep, "w") as f:
            json.dump(PERF, f)
        self.fold = os.path.join(self.d.name, "p.folded")
        with open(self.fold, "w") as f:
            f.write("frame;a 10\n")
        os.environ.pop(pu.TOKEN_ENV, None)

    def tearDown(self):
        self.d.cleanup()
        os.environ.pop(pu.TOKEN_ENV, None)

    def test_url_has_scope_and_no_token(self):
        u = pu.ingest_url("https://n.example/", PERF)
        self.assertEqual(u, "https://n.example/api/perf/ingest?game=g&platform=native&role=client&map=dust&commit=abc")

    def test_env_token_posts_envelope(self):
        os.environ[pu.TOKEN_ENV] = SECRET
        ok, status, msg = pu.upload(self.base, self.rep, self.fold)
        self.assertTrue(ok, msg)
        self.assertEqual(seen["body"]["folded"], "frame;a 10\n")
        self.assertEqual(seen["body"]["report"]["game_id"], "g")
        self.assertNotIn(SECRET, seen["path"] + msg)

    def test_token_file(self):
        tf = os.path.join(self.d.name, "tok")
        with open(tf, "w") as f:
            f.write(SECRET + "\nignored\n")
        self.assertEqual(pu.read_token(tf), SECRET)
        self.assertTrue(pu.upload(self.base, self.rep, "", tf)[0])

    def test_no_token_fails_loudly(self):
        ok, status, msg = pu.upload(self.base, self.rep)
        self.assertFalse(ok)
        self.assertEqual(status, 401)
        self.assertEqual(pu.main([self.rep, "--url", self.base]), 1)

    def test_unreachable(self):
        ok, status, msg = pu.upload("http://127.0.0.1:1", self.rep, timeout=3)
        self.assertFalse(ok)
        self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()
