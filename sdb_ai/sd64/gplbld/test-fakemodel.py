#!/usr/bin/env python3
#
# test-fakemodel.py - a fake AI provider for the tests of sd-ai.exe (from Linux's gplbld/fakemodel.py, S.69 step 2).  Not a guard: it is a module
# test-aihelper-units.py imports by path (named test-* so that assert-current exempts it and the free tier, which runs test-*-units only, does not run it).
# No sd, no elevation, no network but the loopback; the openssl command line (MSYS2's UCRT64 one when PATH has none) makes the throw-away certificates.
#
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-fakemodel.py --selftest
#
# A TLS server on 127.0.0.1 speaking the two wire formats sd-ai speaks, by the path it is asked at:
#   /v1/messages              the Anthropic Messages API       (header x-api-key, anthropic-version)
#   /v1/chat/completions      OpenAI chat completions and its compatibles (header Authorization: Bearer)
# It checks the key against the one it was started with, LOGS every request (path, headers, body) so a test can assert what was sent, and answers as
# a marker in the user's prompt says:  [[plain]] (default)  [[err429]] (a 429 the first time, then plain: the one retry)  [[err429always]]  [[err500]]
#   [[badjson]]  [[shape]]  [[refuse]]  [[ctrl]] (escape sequences, mark bytes and curly quotes)  [[big]] (300,000 characters)  [[redirect]] (a 302 to
#   another host)  [[trunc]]  [[echo]] (the reply is the request body).  GET <base>/models lists MODELS.
# The PKI: a CA (ca.crt), a server certificate it signed for 127.0.0.1 and localhost (server), one for ANOTHER name (wrongname), and a self-signed one
# no CA vouches for (rogue): a client must accept the first and refuse the other two.
#
# START-HISTORY:
# 13 Nov 26 Windows port - from Linux b1d496df's fakemodel.py (RELEASE_1.1 246, the C helper), trimmed to what the Windows guard asks: the toolkit's JSON
#           replies (the AI line's own suites) are not carried.  openssl is found on PATH or at C:\msys64\ucrt64\bin; ThreadingHTTPServer and the PKI are Linux's.
# 8 Nov 26 dm   S.170: GET <base>/models.
# 23 Oct 26 dm  New.
# END-HISTORY

import http.server
import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time

PLAIN_TEXT = "The answer is forty-two."
MODELS = ["fake-large", "fake-small", "models/gemini-fake", "bad name with spaces"]
UCRT_OPENSSL = os.path.join("C:" + os.sep, "msys64", "ucrt64", "bin", "openssl.exe")


def openssl_path():
    return shutil.which("openssl") or (UCRT_OPENSSL if os.path.isfile(UCRT_OPENSSL) else None)


def _openssl(args, cwd):
    exe = openssl_path()
    if exe is None:
        raise RuntimeError("no openssl command line (PATH, or %s)" % UCRT_OPENSSL)
    env = dict(os.environ)
    env["PATH"] = os.path.dirname(exe) + os.pathsep + env.get("PATH", "")
    p = subprocess.run([exe] + args, cwd=cwd, capture_output=True, timeout=60, env=env)
    if p.returncode != 0:
        raise RuntimeError("openssl %s: %s" % (" ".join(args[:2]), p.stderr.decode(errors="replace")[-300:]))


def make_pki(d):
    """Write the CA and the three server certificates into directory d; returns d."""
    _openssl(["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout", "ca.key", "-out", "ca.crt",
              "-subj", "/CN=sdai-test-ca", "-days", "3", "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign",
              "-addext", "subjectKeyIdentifier=hash"], d)
    for stem, san in (("server", "DNS:localhost,IP:127.0.0.1"), ("wrongname", "DNS:other.example.com")):
        _openssl(["req", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout", stem + ".key", "-out", stem + ".csr",
                  "-subj", "/CN=" + stem], d)
        with open(os.path.join(d, stem + ".ext"), "w") as f:
            # strict verification: the leaf needs an authority key identifier, a key usage and a name
            f.write("subjectAltName=%s\nbasicConstraints=CA:FALSE\nauthorityKeyIdentifier=keyid:always\nsubjectKeyIdentifier=hash\n"
                    "keyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\n" % san)
        _openssl(["x509", "-req", "-in", stem + ".csr", "-CA", "ca.crt", "-CAkey", "ca.key", "-CAcreateserial", "-out", stem + ".crt",
                  "-days", "3", "-extfile", stem + ".ext"], d)
    _openssl(["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout", "rogue.key", "-out", "rogue.crt",
              "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1", "-days", "3"], d)
    return d


class FakeModel:
    """The server.  cert is the stem of the certificate to present (server, wrongname or rogue)."""

    def __init__(self, pki, key="test-key-0123456789", cert="server", host="127.0.0.1"):
        self.pki, self.key, self.log, self.count = pki, key, [], {}
        self.models = list(MODELS)
        fake = self

        class H(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def do_POST(self):
                n = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(n)
                h = {k.lower(): v for k, v in self.headers.items()}
                fake.log.append({"path": self.path, "headers": h, "body": body, "method": "POST"})
                status, ctype, out, extra = fake.answer(self.path, h, body)
                self.send_response(status)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(out)))
                for k, v in extra.items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(out)

            def do_GET(self):
                h = {k.lower(): v for k, v in self.headers.items()}
                fake.log.append({"path": self.path, "headers": h, "body": b"", "method": "GET"})
                status, ctype, out, extra = fake.models_answer(self.path, h)
                self.send_response(status)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(os.path.join(pki, cert + ".crt"), os.path.join(pki, cert + ".key"))
        self.httpd = http.server.ThreadingHTTPServer((host, 0), H)
        self.httpd.handle_error = lambda *a: None              # a client that gave up (a refused certificate) is not an error worth a traceback
        self.httpd.socket = ctx.wrap_socket(self.httpd.socket, server_side=True)
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def answer(self, path, h, body):
        anth = path.startswith("/v1/messages")
        ok_key = h.get("x-api-key") == self.key if anth else h.get("authorization") == "Bearer " + self.key
        if not ok_key:
            return self.fail(anth, 401, "invalid key")
        try:
            req = json.loads(body.decode("utf-8"))
            prompt = self.user_text(req)
        except (ValueError, KeyError, IndexError, TypeError):
            return self.fail(anth, 400, "bad request")
        marks = [w for w in ("plain", "err429always", "err429", "err500", "badjson", "shape", "refuse", "ctrl", "big", "redirect", "trunc", "echo")
                 if "[[%s]]" % w in prompt]
        mark = marks[0] if marks else "plain"
        n = self.count[mark] = self.count.get(mark, 0) + 1
        text, stop = PLAIN_TEXT, "end"
        if mark == "err429always" or (mark == "err429" and n == 1):
            return self.fail(anth, 429, "slow down", {"Retry-After": "1"})
        if mark == "err500":
            return self.fail(anth, 500, "server error")
        if mark == "badjson":
            return 200, "application/json", b"{this is not json", {}
        if mark == "shape":
            return 200, "application/json", b'{"unexpected": true}', {}
        if mark == "redirect":
            return 302, "text/plain", b"moved", {"Location": "https://other.example.com/steal"}
        if mark == "ctrl":
            text = "Fine.\x1b[31m red \x1b]52;c;ZXZpbA==\x07 \xfb\xfc\xfd\xfe\xff \u201cquoted\u201d \u2014 dash \u00e9 end\r\n"
        if mark == "big":
            text = "x" * 300000
        if mark == "trunc":
            stop = "length"
        if mark == "echo":
            text = body.decode("utf-8")
        if mark == "refuse":
            stop = "refusal"
        return self.ok(anth, req, text, stop)

    def models_answer(self, path, h):
        anth = "x-api-key" in h
        ok_key = h.get("x-api-key") == self.key if anth else h.get("authorization") == "Bearer " + self.key
        if not ok_key:
            return self.fail(anth, 401, "invalid key")
        if self.models is None or not path.split("?", 1)[0].endswith("/models"):
            return self.fail(anth, 404, "not found")
        out = {"data": [{"id": m, "object": "model"} for m in self.models], "has_more": False}
        return 200, "application/json", json.dumps(out).encode("utf-8"), {}

    @staticmethod
    def user_text(req):
        last = req["messages"][-1]
        if last["role"] != "user":
            raise KeyError("last message is not the user's")
        c = last["content"]
        return c if isinstance(c, str) else "".join(b.get("text", "") for b in c)

    def ok(self, anth, req, text, stop):
        if anth:
            out = {"id": "msg_fake", "type": "message", "role": "assistant", "model": req.get("model"), "content": [{"type": "text", "text": text}],
                   "stop_reason": {"end": "end_turn", "length": "max_tokens", "refusal": "refusal"}[stop], "stop_sequence": None,
                   "usage": {"input_tokens": 11, "output_tokens": 7}}
        else:
            msg = {"role": "assistant", "content": None if stop == "refusal" else text}
            if stop == "refusal":
                msg["refusal"] = "I cannot help with that."
            out = {"id": "chatcmpl-fake", "object": "chat.completion", "model": req.get("model"),
                   "choices": [{"index": 0, "message": msg, "finish_reason": {"end": "stop", "length": "length", "refusal": "stop"}[stop]}],
                   "usage": {"prompt_tokens": 11, "completion_tokens": 7, "total_tokens": 18}}
        return 200, "application/json", json.dumps(out).encode("utf-8"), {}

    @staticmethod
    def fail(anth, status, msg, extra=None):
        if anth:
            out = {"type": "error", "error": {"type": "api_error", "message": msg}}
        else:
            out = {"error": {"message": msg, "type": "api_error", "code": status}}
        return status, "application/json", json.dumps(out).encode("utf-8"), extra or {}


def _selftest():
    import http.client
    passed = failed = 0

    def row(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print("  [PASS] " + name)
        else:
            failed += 1
            print("  [FAIL] " + name + ("   <- " + detail if detail else ""))

    d = tempfile.mkdtemp(prefix="fakemodel-")
    try:
        make_pki(d)
        row("the PKI is made: ca, server, wrongname and rogue certificates exist", all(os.path.exists(os.path.join(d, f)) for f in
            ("ca.crt", "server.crt", "server.key", "wrongname.crt", "rogue.crt")), d)
        fm = FakeModel(d).start()
        ctx = ssl.create_default_context(cafile=os.path.join(d, "ca.crt"))
        c = http.client.HTTPSConnection("127.0.0.1", fm.port, timeout=10, context=ctx)
        body = {"model": "m", "max_tokens": 50, "messages": [{"role": "user", "content": "hello"}]}
        c.request("POST", "/v1/chat/completions", body=json.dumps(body), headers={"Content-Type": "application/json", "Authorization": "Bearer " + fm.key})
        r = c.getresponse()
        raw = r.read()
        c.close()
        row("openai: a right key gets 200 and the text in choices[0].message.content", r.status == 200 and json.loads(raw)["choices"][0]["message"]["content"] == PLAIN_TEXT,
            repr((r.status, raw[:80])))
        fm.stop()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("\nfakemodel selftest: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 and passed > 0 else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(_selftest())
    print("test-fakemodel.py --selftest   (a module for test-aihelper-units.py)")
    sys.exit(2)
