import asyncio
import json
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace as NS

import pytest
from mcp import Client

from eco import agent, graph, server, detect as D
from eco.mcp_server import build_server


@pytest.fixture(scope="module")
def g():
    return graph.open_graph(fresh=True)


READ_ONLY_TOOLS = {"list_cases", "find_overlapping_claims", "find_registry_duplicates", "find_double_retirements", "find_trading_loops",
                   "trace_credit_upstream", "cluster_suspicious", "rank_intermediaries", "list_actions", "run_cypher"}


def test_mcp_tools_are_listed_and_only_one_can_write(g):
    async def go():
        async with Client(build_server(g)) as c:
            names = {t.name for t in (await c.list_tools()).tools}
            res = await c.call_tool("find_double_retirements", {})
            return names, res
    names, res = asyncio.run(go())
    assert names == READ_ONLY_TOOLS | {"propose_action"}                      # ten readers and one note-writer
    assert not any(w in n for n in names for w in ("freeze", "decide", "write", "delete"))
    assert len(json.loads("".join(c.text for c in res.content))["double_retirements"]) == 2


def _payload(res):
    return agent._result_payload(res)


def test_propose_action_writes_a_note_and_never_touches_a_credit():
    eng = server.Engine(graph.open_graph(fresh=True))
    top, second = eng.cases()[0], eng.cases()[1]

    async def go():
        async with Client(build_server(eng.g, lambda: eng.scan_result)) as c:
            first = _payload(await c.call_tool("propose_action", {"case_id": top["id"], "action": "freeze",
                                                                  "rationale": "Three independent signals point at P-19."}))
            again = _payload(await c.call_tool("propose_action", {"case_id": top["id"], "action": "refer",
                                                                  "rationale": "On reflection the evidence is thinner."}))
            errors = [_payload(await c.call_tool("propose_action", a)) for a in (
                {"case_id": top["id"], "action": "launch", "rationale": "Not an action at all, really."},
                {"case_id": "CASE-NOPE", "action": "freeze", "rationale": "There is no such case at all."},
                {"case_id": second["id"], "action": "freeze", "rationale": "short"})]
            listed = _payload(await c.call_tool("list_cases", {}))
            return first, again, errors, listed
    first, again, errors, listed = asyncio.run(go())

    assert first["proposal"]["status"] == "pending" and "Proposal" in first["_trace"]["cypher"]
    assert again["proposal"]["action"] == "refer"
    assert all("error" in e for e in errors)
    pend = D.proposals(eng.g)
    assert set(pend) == {top["id"]} and pend[top["id"]]["action"] == "refer"        # the newer one replaced the older
    assert next(c for c in listed["cases"] if c["id"] == top["id"])["pending_proposal"] == "refer"
    # it is only a note: no credit frozen, no case closed, the proposal hangs off the case's projects
    assert D._rows(eng.g, "MATCH (c:Credit) WHERE c.frozen IS NOT NULL RETURN count(c)")[0][0] == 0
    assert D._rows(eng.g, "MATCH (k:Case) RETURN count(k)")[0][0] == 0
    about = {r[0] for r in D._rows(eng.g, "MATCH (:Proposal {status: 'pending'})-[:ABOUT]->(j:Project) RETURN j.id")}
    assert about == set(top["projects"])
    assert eng.cases()[0]["status"] == "open" and eng.cases()[0]["proposal"]["action"] == "refer"


def test_a_persons_decision_settles_the_proposal_and_is_logged():
    eng = server.Engine(graph.open_graph(fresh=True))
    top, second = eng.cases()[0], eng.cases()[1]
    D.propose(eng.g, top, "freeze", "Double retirement plus an overlap at the same project.")
    D.propose(eng.g, second, "freeze", "Registry duplicate, though no audit on file.")
    agreed = D.decide(eng.g, top, "freeze")                      # the person agrees
    overrode = D.decide(eng.g, second, "refer")                  # the person decides differently
    assert agreed["proposed"] == "freeze" and overrode["proposed"] == "freeze"
    status = dict(D._rows(eng.g, "MATCH (p:Proposal) RETURN p.case, p.status"))
    assert status == {top["id"]: "accepted", second["id"]: "overridden"}
    assert D.proposals(eng.g) == {}
    log = {a["case"]: a for a in D.list_actions(eng.g)["actions"]}
    assert log[top["id"]]["proposed"] == "freeze" and log[second["id"]]["action"] == "refer" and log[second["id"]]["proposed"] == "freeze"

    async def go():
        async with Client(build_server(eng.g, lambda: eng.scan_result)) as c:
            return _payload(await c.call_tool("propose_action", {"case_id": top["id"], "action": "dismiss",
                                                                 "rationale": "Trying to reopen a decided case here."}))
    assert "already frozen" in asyncio.run(go())["error"]       # a decided case takes no new proposal
    assert all(c["proposal"] is None for c in eng.cases() if c["status"] != "open")


def test_cluster_suspicious_uses_wcc(g):
    D.scan(g)
    c = D.cluster_suspicious(g)
    assert c["count"] == 5 and max(len(x["findings"]) for x in c["clusters"]) == 3
    assert "algo.WCC" in c["_trace"]["cypher"]


class FakeModel:
    """Scripted stand-in for the Anthropic client: lists cases, then traces one credit, then answers."""
    def __init__(self):
        self.calls = 0
        self.messages = NS(create=self.create)

    async def create(self, **kw):
        self.calls += 1
        if self.calls == 1:
            return NS(stop_reason="tool_use", content=[NS(type="tool_use", id="t1", name="list_cases", input={})])
        if self.calls == 2:
            assert "CASE-" in kw["messages"][-1]["content"][0]["content"]
            return NS(stop_reason="tool_use", content=[NS(type="tool_use", id="t2", name="trace_credit_upstream", input={"credit_id": "CR-00694"})])
        return NS(stop_reason="end_turn", content=[NS(type="text", text="CR-00694 was retired twice.")])


def test_agent_loop_calls_tools_through_mcp(g):
    out = asyncio.run(agent.ask(g, "What is the riskiest case?", client=FakeModel()))
    assert out["answer"].startswith("CR-00694")
    assert [c["tool"] for c in out["calls"]][:2] == ["list_cases", "trace_credit_upstream"]
    assert all(c["cypher"] for c in out["calls"])


@pytest.fixture()
def api():
    eng = server.Engine(graph.open_graph(fresh=True))
    srv = server.serve(0, "127.0.0.1", eng)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"

    def call(path, body=None, token=None):
        h = {"Content-Type": "application/json"}
        if token:
            h["Authorization"] = f"Bearer {token}"
        req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None, headers=h)
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())
    yield call
    srv.shutdown()


def test_api_case_queue_detail_and_decision(api):
    code, q = api("/api/cases")
    assert code == 200 and len(q["cases"]) == 5 and q["cases"][0]["score"] >= 0.85
    cid = q["cases"][0]["id"]
    code, d = api(f"/api/cases/{cid}")
    assert d["evidence"]["nodes"] and all("x" in n and "y" in n for n in d["evidence"]["nodes"])
    assert any("MATCH" in t["cypher"] for t in d["trace"])
    code, r = api(f"/api/cases/{cid}/decision", {"action": "freeze", "note": "ok"})
    assert code == 200 and r["credits_frozen"] == 4
    assert api(f"/api/cases/{cid}/decision", {"action": "dismiss"})[0] == 409          # already decided
    assert api("/api/cases/CASE-NOPE")[0] == 404
    assert api(f"/api/cases/{q['cases'][1]['id']}/decision", {"action": "launch"})[0] == 400
    assert api("/api/overview")[1]["open"] == 4


def test_api_ask_needs_key_and_token_is_enforced(api, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ECO_LLM_API_KEY", raising=False)
    assert api("/api/ask", {"question": "hi"})[0] == 503
    assert api("/api/ask", {"question": ""})[0] == 400
    monkeypatch.setattr(server, "TOKEN", "secret")
    assert api("/api/cases")[0] == 401 and api("/api/cases", token="wrong")[0] == 401
    assert api("/api/cases", token="secret")[0] == 200 and api("/api/health")[0] == 200


class FakeProposer:
    """Scripted Anthropic-style model: list the cases, record one proposal on the first, then answer."""
    def __init__(self, case_id):
        self.case_id, self.calls = case_id, 0
        self.messages = NS(create=self.create)

    async def create(self, **kw):
        self.calls += 1
        if self.calls == 1:
            return NS(stop_reason="tool_use", content=[NS(type="tool_use", id="t1", name="list_cases", input={})])
        if self.calls == 2:
            return NS(stop_reason="tool_use", content=[NS(type="tool_use", id="t2", name="propose_action", input={
                "case_id": self.case_id, "action": "freeze", "rationale": "Double retirement 0.90 and an overlap 0.60 at the same project."})])
        return NS(stop_reason="end_turn", content=[NS(type="text", text="I proposed a freeze; you decide.")])


def test_api_an_ask_can_leave_a_proposal_that_a_person_then_settles(api, monkeypatch):
    cid = api("/api/cases")[1]["cases"][0]["id"]
    monkeypatch.setattr(agent, "make_client", lambda: FakeProposer(cid))
    code, out = api("/api/ask", {"question": "What should I do about the top case?", "case_id": cid})
    assert code == 200 and [c["tool"] for c in out["calls"]] == ["list_cases", "propose_action"]
    assert "Proposal" in out["calls"][1]["cypher"]
    brief = api("/api/cases")[1]["cases"][0]
    assert brief["proposal"]["action"] == "freeze" and brief["status"] == "open"
    assert api(f"/api/cases/{cid}")[1]["proposal"]["rationale"].startswith("Double retirement")
    assert api("/api/actions")[1]["pending_proposals"][0]["case"] == cid
    code, r = api(f"/api/cases/{cid}/decision", {"action": "freeze"})
    assert code == 200 and r["proposed"] == "freeze" and r["case"]["proposal"] is None
    acts = api("/api/actions")[1]
    assert acts["pending_proposals"] == [] and acts["actions"][0]["proposed"] == "freeze"


def test_evidence_marks_suspicious_links_and_lists_at_risk_credits(api):
    cid = api("/api/cases")[1]["cases"][0]["id"]
    d = api(f"/api/cases/{cid}")[1]
    edges = d["evidence"]["edges"]
    assert all(isinstance(e["flag"], bool) for e in edges)
    assert {e["rel"] for e in edges if e["flag"]} >= {"RETIRED_BY", "SOLD_TO", "COVERS"}
    assert not any(e["flag"] for e in edges if e["rel"] in ("REGISTERED_ON", "ISSUED_FOR"))
    assert len(d["at_risk_ids"]) == d["credits_at_risk"] == 4


def test_built_web_app_is_served_next_to_the_api(tmp_path, monkeypatch):
    import http.client
    (tmp_path / "index.html").write_text("<html>EcoGraph web</html>")
    (tmp_path / "main.dart.js").write_text("console.log(1)")
    monkeypatch.setattr(server, "WEB_DIR", tmp_path)
    srv = server.serve(0, "127.0.0.1", server.Engine(graph.open_graph(fresh=True)))
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    def get(path):
        c = http.client.HTTPConnection("127.0.0.1", srv.server_address[1])
        c.request("GET", path)
        r = c.getresponse()
        return r.status, r.getheader("Content-Type"), r.read()
    try:
        assert get("/") == (200, "text/html", b"<html>EcoGraph web</html>")
        assert get("/main.dart.js")[0:2] == (200, "text/javascript")
        assert get("/some/app/route")[0] == 200                      # single page fallback
        assert get("/missing.js")[0] == 404                          # a missing asset is a 404
        status, _, body = get("/../../../../etc/passwd")
        assert status != 200 or b"root:" not in body                 # no path traversal
        assert get("/api/health")[0] == 200                          # the API still wins on /api
    finally:
        srv.shutdown()


# ---- OpenAI-compatible back end (Gemini, Groq, OpenRouter, OpenAI) --------------------------------------
class FakeProvider:
    """A scripted OpenAI-style /chat/completions server: calls two tools (one with a blank id), then answers."""
    def __init__(self):
        self.requests = []
        outer = self

        class H(BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.requests.append({"path": self.path, "auth": self.headers.get("Authorization"), "ua": self.headers.get("User-Agent"), "body": body})
                n = len(outer.requests)
                if n == 1:
                    msg = {"role": "assistant", "content": None, "tool_calls": [
                        {"id": "c1", "type": "function", "function": {"name": "list_cases", "arguments": "{}"}}]}
                elif n == 2:
                    msg = {"role": "assistant", "content": None, "tool_calls": [
                        {"id": "", "type": "function", "extra_content": {"google": {"thought_signature": "sig"}},
                         "function": {"name": "trace_credit_upstream", "arguments": json.dumps({"credit_id": "CR-00694"})}}]}
                else:
                    msg = {"role": "assistant", "content": "CR-00694 was retired twice."}
                out = json.dumps({"choices": [{"message": msg}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            def log_message(self, *a):
                pass

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_address[1]}/v1"


@pytest.fixture()
def provider_env(monkeypatch):
    fake = FakeProvider()
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("ECO_LLM_API_KEY", "test-key")
    monkeypatch.setenv("ECO_LLM_BASE_URL", fake.base)
    monkeypatch.setenv("ECO_LLM_MODEL", "test-model")
    yield fake
    fake.srv.shutdown()


def test_openai_compatible_agent_loop_uses_the_same_mcp_tools(g, provider_env):
    out = asyncio.run(agent.ask(g, "What is the riskiest case?"))
    assert out["answer"].startswith("CR-00694")
    assert [c["tool"] for c in out["calls"]][:2] == ["list_cases", "trace_credit_upstream"]
    assert all(c["cypher"] for c in out["calls"])

    first, second, third = (r["body"] for r in provider_env.requests)
    assert provider_env.requests[0]["path"] == "/v1/chat/completions"
    assert provider_env.requests[0]["auth"] == "Bearer test-key" and provider_env.requests[0]["ua"] == "ecograph-agent/1.0"
    assert first["model"] == "test-model" and first["messages"][0]["role"] == "system"
    names = {t["function"]["name"] for t in first["tools"]}
    assert {"list_cases", "trace_credit_upstream", "run_cypher"} <= names
    # tools without parameters send none; schema keywords some providers reject are gone
    by_name = {t["function"]["name"]: t["function"] for t in first["tools"]}
    assert "parameters" not in by_name["list_cases"]
    assert by_name["trace_credit_upstream"]["parameters"]["required"] == ["credit_id"]
    assert "title" not in json.dumps(by_name["trace_credit_upstream"]["parameters"])
    assert "default" not in json.dumps(by_name["rank_intermediaries"].get("parameters", {}))
    # the tool result goes back as a `tool` message quoting the call id, with no `name` field (Groq rejects it)
    tool_msg = second["messages"][-1]
    assert tool_msg["role"] == "tool" and tool_msg["tool_call_id"] == "c1" and "name" not in tool_msg and "CASE-" in tool_msg["content"]
    # a blank id from the provider is replaced, and the reasoning signature inside tool_calls is passed back untouched
    echoed = third["messages"][-2]["tool_calls"][0]
    assert echoed["id"] and third["messages"][-1]["tool_call_id"] == echoed["id"]
    assert echoed["extra_content"]["google"]["thought_signature"] == "sig"


class ScriptedProvider:
    """Answers each /chat/completions call with the next canned reply and records what it was sent."""
    def __init__(self, replies):
        self.replies, self.bodies = list(replies), []
        outer = self

        class H(BaseHTTPRequestHandler):
            def do_POST(self):
                outer.bodies.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
                out = json.dumps({"choices": [outer.replies[len(outer.bodies) - 1]]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            def log_message(self, *a):
                pass

        self.srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.srv.server_address[1]}/v1"


def test_an_answer_eaten_by_the_reasoning_cap_is_retried_with_more_room(g, monkeypatch):
    # A reasoning model can spend the whole output cap thinking and return nothing (finish_reason "length").
    fake = ScriptedProvider([{"finish_reason": "length", "message": {"role": "assistant", "content": None}},
                             {"finish_reason": "stop", "message": {"role": "assistant", "content": "Two cases need a freeze."}}])
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("ECO_LLM_MAX_TOKENS", raising=False)
    monkeypatch.setenv("ECO_LLM_API_KEY", "k")
    monkeypatch.setenv("ECO_LLM_BASE_URL", fake.base)
    monkeypatch.setenv("ECO_LLM_MODEL", "m")
    try:
        out = asyncio.run(agent.ask(g, "What should I freeze?"))
    finally:
        fake.srv.shutdown()
    assert out["answer"] == "Two cases need a freeze."
    assert len(fake.bodies) == 2 and fake.bodies[1]["max_tokens"] > fake.bodies[0]["max_tokens"]
    assert fake.bodies[1]["messages"] == fake.bodies[0]["messages"]           # same question, only the cap changed


def test_an_empty_answer_that_stays_empty_says_why_instead_of_looping(g, monkeypatch):
    fake = ScriptedProvider([{"finish_reason": "length", "message": {"content": ""}}] * 3)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("ECO_LLM_API_KEY", "k")
    monkeypatch.setenv("ECO_LLM_BASE_URL", fake.base)
    monkeypatch.setenv("ECO_LLM_MODEL", "m")
    try:
        out = asyncio.run(agent.ask(g, "Anything?"))
    finally:
        fake.srv.shutdown()
    assert len(fake.bodies) == 2                                               # one retry, not a loop
    assert "ECO_LLM_MAX_TOKENS" in out["answer"]


def test_token_budget_gives_gemini_more_room_and_can_be_overridden(monkeypatch):
    monkeypatch.delenv("ECO_LLM_MAX_TOKENS", raising=False)
    monkeypatch.setenv("ECO_LLM_PROVIDER", "groq")
    assert agent.token_budget() == 1500                                        # small: Groq counts the cap against its per-minute limit
    monkeypatch.setenv("ECO_LLM_PROVIDER", " Gemini ")
    assert agent.token_budget() == 8192                                        # Gemini's hidden reasoning uses part of the cap
    monkeypatch.setenv("ECO_LLM_MAX_TOKENS", "3000")
    assert agent.token_budget() == 3000
    monkeypatch.setenv("ECO_LLM_MAX_TOKENS", "lots")
    assert agent.token_budget() == 8192                                        # nonsense falls back to the default


@pytest.mark.parametrize("code, words", [(401, "ECO_LLM_API_KEY"), (404, "ECO_LLM_MODEL"), (429, "rate limit"), (500, "overloaded")])
def test_provider_refusals_come_with_a_plain_hint(monkeypatch, code, words):
    import io

    def refuse(req, timeout=None):
        raise urllib.error.HTTPError(req.full_url, code, "no", {}, io.BytesIO(b'{"error": "overloaded"}'))
    monkeypatch.setattr(urllib.request, "urlopen", refuse)
    with pytest.raises(RuntimeError) as e:
        agent.ChatClient("http://provider.invalid/v1", "k")._post({"model": "m"})
    msg = str(e.value)
    assert msg.startswith(f"The model provider answered {code}.") and words in msg


def test_provider_selection_and_presets(monkeypatch):
    for k in ("ANTHROPIC_API_KEY", "ECO_LLM_API_KEY", "ECO_LLM_PROVIDER", "ECO_LLM_BASE_URL", "ECO_LLM_MODEL"):
        monkeypatch.delenv(k, raising=False)
    assert agent.provider() is None and not agent.available() and agent.model_name() is None
    with pytest.raises(agent.AgentUnavailable):
        agent.make_client()
    monkeypatch.setenv("ECO_LLM_API_KEY", "k")
    monkeypatch.setenv("ECO_LLM_PROVIDER", "Gemini")
    assert agent.provider() == "gemini" and agent.available()
    base, model = agent.llm_settings()
    assert base.endswith("/v1beta/openai") and model == "gemini-3.8-flash" and agent.model_name() == model
    monkeypatch.setenv("ECO_LLM_PROVIDER", "")
    monkeypatch.setenv("ECO_LLM_BASE_URL", "")             # blank values (an empty .env line) fall back to the preset
    with pytest.raises(agent.AgentUnavailable):
        agent.llm_settings()                               # no provider and no URL/model: say what to set
    monkeypatch.setenv("ANTHROPIC_API_KEY", "a")
    assert agent.provider() == "anthropic" and agent.model_name() == agent.MODEL


def test_a_placeholder_key_does_not_shadow_the_real_one(monkeypatch):
    # `export ANTHROPIC_API_KEY=sk-ant-...` copied from instructions would otherwise win over a real Gemini key
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-...")
    monkeypatch.setenv("ECO_LLM_API_KEY", "real-gemini-key")
    monkeypatch.setenv("ECO_LLM_PROVIDER", "gemini")
    assert agent.provider() == "gemini"
    client = agent.make_client()
    assert isinstance(client, agent.ChatClient) and client.api_key == "real-gemini-key"
    monkeypatch.setenv("ECO_LLM_API_KEY", "your-key-here")
    assert agent.provider() is None and not agent.available()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-api03-fake")
    assert agent.provider() == "anthropic"


def test_env_file_fills_missing_variables_only(tmp_path, monkeypatch):
    from eco.envfile import load_env
    f = tmp_path / ".env"
    f.write_text("# comment\nECO_A=one   # trailing\nexport ECO_B=\"two words\"\nECO_C=\nECO_D=kept-from-file\nnot a line\n")
    for k in ("ECO_A", "ECO_B", "ECO_C"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("ECO_D", "already-set")
    assert load_env(f) == f
    import os
    assert os.environ["ECO_A"] == "one" and os.environ["ECO_B"] == "two words"
    assert "ECO_C" not in os.environ and os.environ["ECO_D"] == "already-set"
    for k in ("ECO_A", "ECO_B"):
        monkeypatch.delenv(k, raising=False)


def test_env_example_copied_as_it_is_leaves_the_optional_settings_unset(tmp_path, monkeypatch):
    """The README says: copy .env.example to .env and add a key. A blank value followed by a comment must stay blank."""
    import os
    from pathlib import Path
    from eco.envfile import load_env
    names = ("ANTHROPIC_API_KEY", "ECO_MODEL", "ECO_LLM_PROVIDER", "ECO_LLM_API_KEY", "ECO_LLM_MODEL", "ECO_LLM_BASE_URL",
             "ECO_LLM_MAX_TOKENS", "ECO_TOKEN", "ECO_ASK_PER_MIN", "ECO_ASK_PER_DAY", "FALKORDB_HOST")
    for k in names:
        monkeypatch.delenv(k, raising=False)
    f = tmp_path / ".env"
    f.write_text((Path(__file__).resolve().parent.parent / ".env.example").read_text().replace("ECO_LLM_API_KEY=", "ECO_LLM_API_KEY=my-key"))
    load_env(f)
    got = {k: os.environ.get(k) for k in names}
    for k in names:
        monkeypatch.delenv(k, raising=False)
    assert got["ECO_LLM_PROVIDER"] == "gemini" and got["ECO_LLM_API_KEY"] == "my-key"
    assert got["ECO_LLM_MODEL"] is None and got["ECO_LLM_BASE_URL"] is None and got["ECO_LLM_MAX_TOKENS"] is None
    assert not any(v and v.startswith("#") for v in got.values())
