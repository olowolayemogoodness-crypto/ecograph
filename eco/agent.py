import asyncio
import json
import os
import urllib.error
import urllib.request

from mcp import Client

from eco.mcp_server import build_server

MODEL = os.environ.get("ECO_MODEL", "claude-sonnet-5-5")


PRESETS = {
    "gemini": ("https://generativelanguage.googleapis.com/v1beta/openai", "gemini-3.8-flash"),
    "groq": ("https://api.groq.com/openai/v1", "llama-3.3-70b-versatile"),
    "openrouter": ("https://openrouter.ai/api/v1", ""),
}

SYSTEM = """You are EcoGraph, an investigation assistant for a carbon-credit integrity reviewer. You help a person find double counting and fraud in a voluntary carbon-credit ledger stored as a graph, and decide what to do.

Rules:
- Answer only from tool results. Never state a credit id, project, count, tonnes figure, score or cause you did not get from a tool.
- Pick the smallest set of tools that answers the question. Start with list_cases for an overview. Prefer the specific tools; use run_cypher only as a last resort.
- Explain a risk score by naming its signals and weights from the tool result. The score is a rule of thumb, not a probability, and a high network position (betweenness) is not proof of wrongdoing.
- Say plainly when the evidence is thin or a pattern could be innocent (for example an ended project followed by a new one, or two parties swapping different credits).
- You can recommend a freeze, a referral to the registries, or a dismissal. When the reviewer asks you to flag, triage or say what to do about cases, record each recommendation with propose_action: once per case, only after you have looked at its signals, never on a case that is already decided, with one sentence that names the signals and their weights. A proposal is a note for the reviewer. You cannot freeze, refer or dismiss anything: a person decides in the app.
- All data is synthetic. Keep answers short: lead with the answer, then the facts behind it."""

STEP_LIMIT = "I could not finish within the step limit. Try a narrower question."


class AgentUnavailable(Exception):
    pass


def _key(name):
    v = os.environ.get(name, "").strip()
    return "" if (not v or "..." in v or "\u2026" in v or v.lower().startswith(("your", "paste", "<"))) else v


def provider():
    if _key("ANTHROPIC_API_KEY"):
        return "anthropic"
    if _key("ECO_LLM_API_KEY"):
        return os.environ.get("ECO_LLM_PROVIDER", "").strip().lower() or "openai-compatible"
    return None


def available():
    return provider() is not None


def llm_settings():
    base, model = PRESETS.get(os.environ.get("ECO_LLM_PROVIDER", "").strip().lower(), ("", ""))
    base = (os.environ.get("ECO_LLM_BASE_URL") or base).rstrip("/")
    model = os.environ.get("ECO_LLM_MODEL") or model
    if not base or not model:
        raise AgentUnavailable("Set ECO_LLM_PROVIDER to gemini or groq, or set both ECO_LLM_BASE_URL and ECO_LLM_MODEL.")
    return base, model


def model_name():
    p = provider()
    if p == "anthropic":
        return MODEL
    if p:
        try:
            return llm_settings()[1]
        except AgentUnavailable:
            return None
    return None


HTTP_HINTS = {
    401: "It rejected the key: check ECO_LLM_API_KEY.",
    403: "It rejected the key: check ECO_LLM_API_KEY.",
    404: "It does not know that model or address: check ECO_LLM_PROVIDER and ECO_LLM_MODEL.",
    429: "The free rate limit was reached: wait a minute and ask again.",
}


class ChatClient:

    def __init__(self, base_url, api_key, timeout=60):
        self.base_url, self.api_key, self.timeout = base_url.rstrip("/"), api_key, timeout

    async def chat(self, **payload):
        return await asyncio.to_thread(self._post, payload)

    def _post(self, payload):
        req = urllib.request.Request(
            self.base_url + "/chat/completions", data=json.dumps(payload).encode(), method="POST",
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {self.api_key}",
                     "User-Agent": "ecograph-agent/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            said = (f"The model provider answered {e.code}.", HTTP_HINTS.get(e.code, ""), e.read().decode("utf-8", "replace")[:300])
            raise RuntimeError(" ".join(part for part in said if part)) from None
        except urllib.error.URLError as e:
            raise RuntimeError(f"Could not reach the model provider: {e.reason}") from None


def make_client():
    if _key("ANTHROPIC_API_KEY"):
        import anthropic
        return anthropic.AsyncAnthropic(api_key=_key("ANTHROPIC_API_KEY"))
    if _key("ECO_LLM_API_KEY"):
        return ChatClient(llm_settings()[0], _key("ECO_LLM_API_KEY"))
    raise AgentUnavailable("Set ANTHROPIC_API_KEY (Claude) or ECO_LLM_API_KEY (Gemini, Groq or another OpenAI-compatible provider) to enable the agent.")


def _schema_of(t):
    return getattr(t, "input_schema", None) or getattr(t, "inputSchema", None) or {"type": "object", "properties": {}}


def _tool_defs(tools):
    return [{"name": t.name, "description": t.description or "", "input_schema": _schema_of(t)} for t in tools]


_DROP = {"title", "default", "additionalProperties", "$schema", "$defs"}


def _clean(s):
    if isinstance(s, dict):
        return {k: ({n: _clean(p) for n, p in v.items()} if k == "properties" and isinstance(v, dict) else _clean(v))
                for k, v in s.items() if k not in _DROP}
    if isinstance(s, list):
        return [_clean(x) for x in s]
    return s


def _openai_tools(tools):
    out = []
    for t in tools:
        fn = {"name": t.name, "description": t.description or ""}
        params = _clean(_schema_of(t))
        if params.get("properties"):
            fn["parameters"] = params
        out.append({"type": "function", "function": fn})
    return out


def _result_payload(res):
    sc = getattr(res, "structured_content", None) or getattr(res, "structuredContent", None)
    if sc is not None:
        return sc.get("result", sc) if isinstance(sc, dict) and set(sc) == {"result"} else sc
    text = "".join(getattr(c, "text", "") for c in getattr(res, "content", []) or [])
    try:
        return json.loads(text)
    except ValueError:
        return {"text": text}


async def _run_tool(mc, name, args, calls):
    try:
        payload = _result_payload(await mc.call_tool(name, args))
    except Exception as e:
        payload = {"error": str(e)[:300]}
    tr = payload.pop("_trace", None) if isinstance(payload, dict) else None
    for t in (tr if isinstance(tr, list) else [tr] if tr else []):
        calls.append({"tool": name, "input": args, "detail": t.get("detail"), "cypher": t.get("cypher")})
    if not tr:
        calls.append({"tool": name, "input": args, "detail": "no graph trace", "cypher": None})
    return json.dumps(payload, default=str)[:12000]


async def _loop_anthropic(mc, client, tools, question, model, max_steps):
    defs, calls = _tool_defs(tools), []
    messages = [{"role": "user", "content": question}]
    for _ in range(max_steps):
        resp = await client.messages.create(model=model, max_tokens=1500, system=SYSTEM, tools=defs, messages=messages)
        blocks = [{"type": "text", "text": b.text} if b.type == "text" else
                  {"type": "tool_use", "id": b.id, "name": b.name, "input": b.input}
                  for b in resp.content if b.type in ("text", "tool_use")]
        messages.append({"role": "assistant", "content": blocks})
        if resp.stop_reason != "tool_use":
            return {"answer": "".join(b["text"] for b in blocks if b["type"] == "text").strip(),
                    "calls": calls, "tools_available": [t.name for t in tools]}
        results = []
        for b in [b for b in blocks if b["type"] == "tool_use"]:
            results.append({"type": "tool_result", "tool_use_id": b["id"],
                            "content": await _run_tool(mc, b["name"], b["input"], calls)})
        messages.append({"role": "user", "content": results})
    return {"answer": STEP_LIMIT, "calls": calls, "tools_available": [t.name for t in tools]}


def token_budget():
    try:
        return int(os.environ["ECO_LLM_MAX_TOKENS"])
    except (KeyError, ValueError):
        return 8192 if os.environ.get("ECO_LLM_PROVIDER", "").strip().lower() == "gemini" else 1500


async def _loop_chat(mc, client, tools, question, model, max_steps):
    defs, calls = _openai_tools(tools), []
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": question}]
    budget, widened, step = token_budget(), False, 0
    while step < max_steps:
        resp = await client.chat(model=model, messages=messages, tools=defs, max_tokens=budget)
        choice = (resp.get("choices") or [{}])[0]
        msg = choice.get("message") or {}
        tool_calls = msg.get("tool_calls") or []
        text = (msg.get("content") or "").strip()
        if not tool_calls and not text and choice.get("finish_reason") == "length" and not widened:
            budget, widened = min(budget * 4, 16000), True
            continue
        if not tool_calls:
            return {"answer": text or ("The model ran out of room before it answered. Set ECO_LLM_MAX_TOKENS higher."
                                       if choice.get("finish_reason") == "length" else "The model returned no answer. Try again."),
                    "calls": calls, "tools_available": [t.name for t in tools]}
        for i, tc in enumerate(tool_calls):
            if not tc.get("id"):
                tc["id"] = f"call_{step}_{i}"

        messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": tool_calls})
        for tc in tool_calls:
            fn = tc.get("function") or {}
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except ValueError:
                args = {}
            messages.append({"role": "tool", "tool_call_id": tc["id"],
                             "content": await _run_tool(mc, fn.get("name", ""), args if isinstance(args, dict) else {}, calls)})
        step += 1
    return {"answer": STEP_LIMIT, "calls": calls, "tools_available": [t.name for t in tools]}


async def ask(g, question, cases_fn=None, client=None, model=None, max_steps=10):
    client = client or make_client()
    chat_style = hasattr(client, "chat")
    model = model or (llm_settings()[1] if chat_style else MODEL)
    async with Client(build_server(g, cases_fn)) as mc:
        tools = (await mc.list_tools()).tools
        loop = _loop_chat if chat_style else _loop_anthropic
        return await loop(mc, client, tools, question, model, max_steps)
