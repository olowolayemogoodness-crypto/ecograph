import asyncio
import hmac
import json
import mimetypes
import os
import re
import threading
import time
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

from eco.envfile import load_env

if __name__ == "__main__":
    load_env()

from eco import agent, detect as D, graph

TOKEN = os.environ.get("ECO_TOKEN", "")

WEB_DIR = Path(os.environ.get("ECO_WEB_DIR") or Path(__file__).resolve().parent.parent / "web_app")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".mjs")
ASK_PER_MIN = int(os.environ.get("ECO_ASK_PER_MIN", "10"))
ASK_PER_DAY = int(os.environ.get("ECO_ASK_PER_DAY", "300"))
TYPE_TOOL = {"overlap": "find_overlapping_claims", "registry_duplicate": "find_registry_duplicates",
             "double_retirement": "find_double_retirements", "loop": "find_trading_loops"}


class Engine:
    def __init__(self, g=None):
        self.lock = threading.RLock()
        self.g = g or graph.open_graph(fresh=True)
        self.scan_result = None
        self.hits = {}
        self.day = {"stamp": time.strftime("%Y-%m-%d"), "n": 0}
        self.refresh()

    def refresh(self):
        with self.lock:
            self.scan_result = D.scan(self.g)

    def cases(self):
        dec, props = D.decisions(self.g), D.proposals(self.g)
        out = []
        for c in self.scan_result["cases"]:
            d = dec.get(c["id"], {})
            status = d.get("status") or "open"
            out.append({**c, "status": status, "note": d.get("note"), "decided_at": d.get("decided_at"),
                        "proposal": props.get(c["id"]) if status == "open" else None})
        return out

    def get(self, cid):
        return next((c for c in self.cases() if c["id"] == cid), None)

    def allow_ask(self, ip):
        now = time.time()
        today = time.strftime("%Y-%m-%d")
        if self.day["stamp"] != today:
            self.day.update(stamp=today, n=0)
        recent = [t for t in self.hits.get(ip, []) if now - t < 60]
        if len(recent) >= ASK_PER_MIN or self.day["n"] >= ASK_PER_DAY:
            self.hits[ip] = recent
            return False
        self.hits[ip] = recent + [now]
        self.day["n"] += 1
        return True


def brief(c):
    keep = ("id", "title", "score", "band", "suggested", "types", "projects", "credits_at_risk", "tonnes_at_risk",
            "credits_frozen", "summary", "status", "note", "decided_at", "proposal")
    return {k: c.get(k) for k in keep}


def detail(eng, c):
    wanted = {TYPE_TOOL[t] for t in c["types"]} | {"cluster_suspicious"}
    trace = [t for t in eng.scan_result["trace"] if t["tool"] in wanted or (t["tool"] == "scan" and any(s["signal"] == "no_audit" for s in c["signals"]))]
    return {**brief(c), "findings": c["findings"], "signals": c["signals"], "evidence": c["evidence"], "trace": trace,
            "at_risk_ids": c.get("at_risk_ids", [])[:60],
            "how_to_read": "Score = 1 - product of (1 - weight) over the signals. A rule of thumb, not a probability. "
                           f"Freeze is suggested from {D.FREEZE_AT}, referral from {D.REVIEW_AT}. A person decides."}


def make_handler(eng):
    class H(BaseHTTPRequestHandler):
        def _send(self, obj, code=200):
            body = json.dumps(obj, default=str).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _static(self, path):
            root = Path(WEB_DIR).resolve()
            if not (root / "index.html").is_file():
                return False
            rel = path.lstrip("/") or "index.html"
            f = (root / rel).resolve()
            if f != root and root not in f.parents:
                return False
            if f.is_dir():
                f = f / "index.html"
            if not f.is_file():
                if "." in rel.rsplit("/", 1)[-1]:
                    return False
                f = root / "index.html"
            data = f.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(str(f))[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(data)
            return True

        def _authed(self, path):
            if not TOKEN or path == "/api/health":
                return True
            got = self.headers.get("Authorization", "")
            return hmac.compare_digest(got, f"Bearer {TOKEN}")

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            try:
                return json.loads(self.rfile.read(min(n, 20000)) or b"{}")
            except ValueError:
                return {}

        def do_OPTIONS(self):
            self._send({})

        def do_GET(self):
            path = urlparse(self.path).path.rstrip("/") or "/"
            if not path.startswith("/api/") and self._static(path):
                return
            if path == "/":
                return self._send({"service": "EcoGraph API", "docs": "see API_CONTRACT.md", "health": "/api/health"})
            if not self._authed(path):
                return self._send({"error": "unauthorised"}, 401)
            with eng.lock:
                if path == "/api/health":
                    return self._send({"ok": True, "cases": len(eng.scan_result["cases"]), "agent": agent.available(),
                                       "provider": agent.provider(), "model": agent.model_name(),
                                       "database": "falkordb-server" if os.environ.get("FALKORDB_HOST") else "falkordb-embedded"})
                if path == "/api/overview":
                    cs = eng.cases()
                    open_ = [c for c in cs if c["status"] == "open"]
                    return self._send({**D.overview(eng.g), "cases": len(cs), "open": len(open_),
                                       "freeze_suggested": sum(c["suggested"] == "freeze" for c in open_),
                                       "tonnes_at_risk": sum(c["tonnes_at_risk"] for c in open_),
                                       "synthetic": True})
                if path == "/api/cases":
                    return self._send({"cases": [brief(c) for c in eng.cases()]})
                m = re.fullmatch(r"/api/cases/([A-Z0-9-]+)", path)
                if m:
                    c = eng.get(m.group(1))
                    return self._send(detail(eng, c)) if c else self._send({"error": "no such case"}, 404)
                m = re.fullmatch(r"/api/credits/([A-Z0-9-]+)", path)
                if m:
                    r = D.trace_credit_upstream(eng.g, m.group(1))
                    return self._send(r, 404 if "error" in r else 200)
                if path == "/api/actions":
                    return self._send(D.list_actions(eng.g))
            self._send({"error": "not found"}, 404)

        def do_POST(self):
            path = urlparse(self.path).path.rstrip("/")
            if not self._authed(path):
                return self._send({"error": "unauthorised"}, 401)
            body = self._body()
            m = re.fullmatch(r"/api/cases/([A-Z0-9-]+)/decision", path)
            if m:
                with eng.lock:
                    c = eng.get(m.group(1))
                    if not c:
                        return self._send({"error": "no such case"}, 404)
                    if c["status"] != "open":
                        return self._send({"error": f"Case already {c['status']}."}, 409)
                    try:
                        res = D.decide(eng.g, c, body.get("action"), str(body.get("note") or ""))
                    except ValueError as e:
                        return self._send({"error": str(e)}, 400)
                    eng.refresh()
                    return self._send({**res, "case": detail(eng, eng.get(c["id"]))})
            if path == "/api/ask":
                question = str(body.get("question") or "").strip()[:500]
                if not question:
                    return self._send({"error": "Ask a question first."}, 400)
                ip = (self.headers.get("X-Forwarded-For") or self.client_address[0]).split(",")[0].strip()
                with eng.lock:
                    if not eng.allow_ask(ip):
                        return self._send({"error": "Too many questions. Try again in a minute."}, 429)
                    cid = body.get("case_id")
                    c = eng.get(cid) if cid else None
                    if c:
                        question = (f"[The reviewer is looking at {c['id']}: {c['title']}, projects {', '.join(c['projects'])}.]\n" + question)
                    try:
                        out = asyncio.run(agent.ask(eng.g, question, cases_fn=lambda: eng.scan_result))
                    except agent.AgentUnavailable as e:
                        return self._send({"error": str(e), "unavailable": True}, 503)
                    except BaseException as e:
                        while getattr(e, "exceptions", None):
                            e = e.exceptions[0]
                        import traceback
                        traceback.print_exception(e)
                        return self._send({"error": f"The agent failed: {type(e).__name__}: {str(e)[:300]}"}, 502)
                    return self._send(out)
            if path == "/api/reset":
                with eng.lock:
                    graph.load(eng.g)
                    eng.refresh()
                    return self._send({"ok": True, "cases": len(eng.scan_result["cases"])})
            self._send({"error": "not found"}, 404)

        def log_message(self, fmt, *args):
            pass
    return H


def serve(port=8000, host="0.0.0.0", eng=None):
    eng = eng or Engine()
    return ThreadingHTTPServer((host, port), make_handler(eng))


if __name__ == "__main__":
    import sys
    port = int(os.environ.get("PORT") or (sys.argv[1] if len(sys.argv) > 1 else 8000))
    if not TOKEN:
        print("ECO_TOKEN is not set: the API is open. Fine for local runs, not for a public deployment.")
    print(f"EcoGraph API on http://0.0.0.0:{port}  |  agent: {agent.provider() or 'off (set ANTHROPIC_API_KEY or ECO_LLM_API_KEY)'}")
    serve(port).serve_forever()
