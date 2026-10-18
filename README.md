<div align="center">

<img src="docs/logo.png" alt="EcoGraph logo" width="140">

# EcoGraph

**Count every tonne once.**

An AI agent that finds carbon credits counted twice, by reasoning over a **FalkorDB** graph.
A person makes every decision.

[Live demo](#links) · [Android app](#links) · [Demo video](#links) · [Blog post](#links) · [How it works](#how-it-works) · [Run it](#set-it-up)

Built for **Graph Hacks: Context for AI Agents** (WeMakeDevs x FalkorDB) · **Track 1: Agents That Act on Connected Data**

</div>

> All data is synthetic. Registries, projects and companies are invented. Nothing here accuses a real party.

## The problem

A carbon credit is one tonne of CO2, counted once. The whole market rests on that rule, and it is hard to check, because the ways to break it are not visible in a table of projects:

* **Retired twice.** One credit is claimed by two companies.
* **Same land, twice.** Two projects on two registries claim the same forest.
* **Sold in a circle.** The same credits go around a ring of holders to fake demand.

Each is a question about *paths* between projects, land, credits and buyers. Published studies show how weak the checks are: a 2024 study of 2,346 projects found most credits did not reflect real emission cuts, and an audit study found auditors missed the flaws in two of three flagged projects. Checks look at one project at a time. Double counting lives between them. In June 2025 a registry put a cookstove project on hold over double-counting claims (the developer denies them), and the only way to find out was a manual review.

## What EcoGraph does

EcoGraph stores the carbon ledger in **FalkorDB** and gives an AI agent **graph queries and graph algorithms as MCP tools**. The agent asks the graph questions, ranks the suspicious cases and writes a one-line recommendation. The reviewer opens a case, sees the evidence as a path they can check, and chooses **freeze**, **refer to registries** or **dismiss**.

* The agent can recommend. **It cannot freeze anything.** Exactly one tool writes, and it writes a note.
* Every decision is logged next to what the agent proposed, so you can see whether a person agreed.
* A scan of the whole demo ledger (1,900 nodes, 4,125 edges) takes about 0.15 seconds.
* On the demo ledger it finds **7 of 7 planted frauds with 0 false alarms** on 6 look-alike decoys. That shows the queries work as claimed; it says nothing about accuracy on messy real data.

```
 Flutter app (iOS, Android, web)  --- JSON over HTTPS --->  eco/server.py  --->  FalkorDB
   home, cases, graph, trace, ask                              |                  graph + algorithms
   freeze / refer / dismiss                                    +-- eco/agent.py --> 11 MCP tools (10 read, 1 note)
                                                                    model: Gemini, Claude, or Groq
```

## How it works

1. **Scans** the ledger with plain OpenCypher detectors and writes each hit as a `Finding` node.
2. **Clusters** findings with `algo.WCC`, so findings that share a project or credit become one case instead of three unrelated alerts.
3. **Scores** each case with an explainable rule: named signals with weights, combined as `1 - Π(1 - weight)`. It is a rule of thumb, not a probability, and the app says so.
4. **Explains** with the path: the subgraph (suspicious links dashed in red), the signals, and the exact Cypher behind it.
5. **Acts, with a human.** The reviewer confirms on a screen that lists the credits affected. The decision is written back to the graph (`Case`, `AuditLog`, `FLAGS`, `Credit.frozen`) so memory survives a re-scan.
6. **Proposes, never decides.** Asked to triage, the agent records a recommendation as a `Proposal` node through one MCP tool, `propose_action`. Nothing else changes until a person decides.
7. **Answers questions** in plain language. The model picks among 11 MCP tools, and the app lists every tool call and query it made.

## The app

One Flutter codebase for iOS, Android and web, with a soft, rounded interface. On a phone: a splash and welcome, then five tabs.

| Tab | What you do |
|---|---|
| Home | See how many cases need a decision and the tonnes at risk, and start with the top case |
| Cases | Browse the queue, ordered by score |
| Ask | Ask the agent anything, or tap "Triage every open case" |
| Trace | Follow one credit from its retirement back to the land |
| History | See each decision, and whether you agreed with the agent |

A case has **Evidence / Why / Query / Ask** tabs and a decision bar. In a window 1320 px wide or more it becomes a three-pane review console. The design system lives in `app/lib/theme.dart`.

## Set it up

You need **Python 3.12 or newer**. Flutter is only needed if you want to change or run the phone app; the web app is already built and included.

### 1. Get the code

```bash
git clone https://github.com/olowolayemogoodness-crypto/ecograph.git
cd ecograph
```

### 2. Start the backend

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python -m eco.server 8000
```

Open http://localhost:8000. You should see the app, already loaded with the demo ledger. `http://localhost:8000/api/health` should answer `"ok": true`.

The database is FalkorDB running inside the Python process, so there is nothing else to install. (On an Apple Silicon Mac this needs macOS 15 or newer. On anything older, use Docker, below.)

### 3. Turn on the AI agent (optional)

Everything works without this except the **Ask** tab. To switch it on:

1. Get a free Gemini key at https://aistudio.google.com/apikey.
2. Copy the example settings file: `cp .env.example .env`
3. Open `.env` and fill in these two lines:
   ```
   ECO_LLM_PROVIDER=gemini
   ECO_LLM_API_KEY=your-key-here
   ```
4. Restart the backend. `http://localhost:8000/api/health` now shows `"agent": true` and the model name.

`.env` is git-ignored, so your key is never published. Prefer Claude or Groq? Use `ANTHROPIC_API_KEY=...`, or `ECO_LLM_PROVIDER=groq`. The comments in `.env.example` list every option.

### 4. Run the phone app (optional)

Keep the backend running, then in a second terminal:

```bash
cd app
flutter pub get
flutter run -d chrome      # web
flutter run                # iOS simulator or Android emulator
```

The app finds the backend on its own (`127.0.0.1:8000`, or `10.0.2.2:8000` on the Android emulator). To rebuild the web app that the backend serves:

```bash
cd app && flutter build web --release
rm -rf ../web_app && cp -r build/web ../web_app
```

### 5. Check that it works

```bash
python -m pytest -q          # 34 tests
python -m eco.evaluate       # should find 7 of 7 planted frauds, 0 false alarms
```

### Docker instead

```bash
docker compose up --build    # app and API on :8000, FalkorDB server on :6379
```

### Put it online

Push the repo to GitHub, then on https://render.com choose **New > Blueprint**, pick this repo and paste your Gemini key when asked. Render reads `render.yaml` and builds the `Dockerfile`. Details are in [DEPLOY.md](DEPLOY.md).

### Use it from Claude Desktop or another MCP client

`python -m eco.mcp_server` speaks MCP over stdio. Every endpoint is described in [API_CONTRACT.md](API_CONTRACT.md).

## Try it: a one-minute walk-through

1. **Home** shows 5 cases that need a decision and 27,880 tonnes at risk.
2. **Ask** tab: tap *Triage every open case*. The agent calls the graph tools and ranks the cases.
3. **Cases**: open `CASE-3774F`, the top case. The graph shows the problem path.
4. **Trace**: search `CR-00694` to follow one credit from its retirement back to the land.
5. Open the case and choose **Freeze**, then confirm.
6. **History** shows your decision and whether you agreed with the agent. *Settings > Reset demo data* starts over.

## Graph data model

```
(Project)-[:COVERS]->(LandParcel)           (Project)-[:REGISTERED_ON]->(Registry)
(Project)-[:VERIFIED_BY]->(AuditReport)     (Project)-[:DEVELOPED_BY]->(Buyer {kind:'developer'})
(Credit)-[:ISSUED_FOR]->(Project)           (Credit)-[:RETIRED_BY {day, claim}]->(Buyer)
(Buyer)-[:SOLD_TO {credit, day, price}]->(Buyer)

written by the scan:     (Finding {type, weight})-[:INVOLVES]->(Project | Credit)
written by the agent:    (Proposal {case, action, rationale, status})-[:ABOUT]->(Project)      a note, nothing more
written by a person:     (Case {status})-[:FLAGS]->(Credit),  (AuditLog {proposed})-[:RECORDS]->(Case),  Credit.frozen
```
A `Proposal` is pending until a person decides the case; it then becomes `accepted` (same action) or `overridden` (different action), and the audit entry keeps what the agent had proposed. It hangs off the case's projects because `Finding` nodes are rebuilt on every scan.
Synthetic ledger: about 1,900 nodes and 4,100 edges (1,634 credits, 121 buyers, 41 projects, 60 land parcels, 3 registries), generated by `eco/graph.py` with a fixed seed.

## Queries and algorithms

All in `eco/detect.py`. Each detector returns its rows plus the exact query, which the app shows.

| Tool | What it finds | FalkorDB feature |
|---|---|---|
| `find_overlapping_claims` | Two active projects covering the same parcel | Multi-hop pattern `(p1)-[:COVERS]->(lp)<-[:COVERS]-(p2)` with aggregation |
| `find_registry_duplicates` | Same land listed on two registries | Same pattern; parcel sets compared |
| `find_double_retirements` | One credit retired by two buyers | Aggregation over `RETIRED_BY` |
| `find_trading_loops` | One credit sold around a circle of 3 to 6 holders | Variable-length cycle `*3..6` with an edge-property filter |
| `trace_credit_upstream` | A credit's whole path from retirement back to the land | Multi-hop with `OPTIONAL MATCH` |
| `cluster_suspicious` | Which findings belong to one scheme | **`algo.WCC`** over `Finding`/`Project`/`Credit` |
| `rank_intermediaries` | Who sits on the most sale routes | **`algo.betweenness`** (context only) |
| `list_cases`, `list_actions`, `run_cypher` | Scored cases, past decisions and waiting proposals, read-only escape hatch | `ro_query` rejects writes |
| `propose_action` | The agent's recommended action on one open case (the only tool that writes) | Creates a `Proposal` node and an `ABOUT` edge; touches no credit, refuses decided cases |

The loop detector, the part that is easy to get wrong:
```cypher
MATCH ()-[x:SOLD_TO]->()
WITH x.credit AS cid, count(x) AS hops WHERE hops >= 3
MATCH p = (b:Buyer)-[:SOLD_TO*3..6 {credit: cid}]->(b)
WHERE all(n IN nodes(p) WHERE b.id <= n.id)         -- report each circle once
RETURN cid, [n IN nodes(p) | n.id] AS ring, [e IN relationships(p) | e.day] AS days
```
A first version without the `{credit: cid}` filter explored every sale path and did not finish in two minutes; with it, the query returns in well under a second. Two brokers swapping *different* credits is not a loop, and is not returned.

Overlap and double retirement:
```cypher
MATCH (p1:Project)-[:COVERS]->(lp:LandParcel)<-[:COVERS]-(p2:Project)
WHERE p1.id < p2.id AND p1.status = 'ACTIVE' AND p2.status = 'ACTIVE'
...
MATCH (c:Credit)-[r:RETIRED_BY]->(b:Buyer)
WITH c, collect({buyer: b.id, day: r.day, claim: r.claim}) AS claims WHERE size(claims) > 1
```

## The agent

`eco/agent.py` runs a plain tool-use loop. It opens an in-process MCP connection to `eco/mcp_server.py` (the same protocol an outside client uses), lists the 11 tools, lets the model choose, and records the Cypher behind every call for the app's trace. Rules in the system prompt: answer only from tool results, explain scores by their named signals, say when evidence is thin, and recommend but never decide. Ten tools are read-only. The eleventh, `propose_action`, can write one thing: a `Proposal` note on an open case. No tool can freeze, refer or dismiss, so "a person decides" is enforced by the tool list, not by trust in the prompt, and a test checks that exactly one tool can write and that a proposal never touches a credit. The Claude loop and the OpenAI-compatible loop (Gemini, Groq) share one tool runner and are tested against scripted models, including a mock HTTP provider.

## How the score works

| Signal | Weight | Meaning |
|---|---|---|
| `double_retirement` | 0.90 | The same credit retired by two buyers |
| `registry_duplicate` | 0.80 | The same land on two registries |
| `overlap` | 0.60 | Two active projects claim the same land |
| `loop` | 0.55 | A credit came back to a holder it had passed through |
| `no_audit` | 0.15 | A project in the case has no audit report (corroborates only, never raises a case alone) |

`score = 1 - Π(1 - weight)`. Freeze is *suggested* from 0.85, referral from 0.50. These weights are a documented judgement, not fitted to data. In the demo ledger the ring around P-19 scores 0.985 because three independent signals point at the same project.

## Evaluation

`python -m eco.evaluate` plants 7 frauds (2 overlaps, 1 registry duplicate, 2 double retirements, 2 loops) and 6 look-alike decoys: neighbouring parcels, an ended project followed by a new one on the same land, a five-hop honest resale chain, two brokers swapping different credits, a large honest buyer, and unaudited projects. Result: **7 of 7 found, 0 false alarms**. Because the frauds are planted by the same code that checks them, this shows the queries do what they claim and stay quiet on the decoys. It says nothing about accuracy on a real registry, whose data is messier.

## Design choices

* **Decision support, not autopilot.** The agent may write a note (a proposal) and nothing else. Freezing a credit is a person's decision, confirmed on a screen that lists the credits, then logged with who and when, and with what the agent had proposed.
* **Honest uncertainty.** Scores are labelled a rule of thumb; betweenness is labelled context, not proof; decoys exist to show the queries can say "no".
* **FalkorDB is the engine.** Findings, clusters, decisions and memory all live in the graph; the app and agent read it, they do not keep their own copy.
* **No model key on the phone.** The app calls this API; only the server holds a key.
* **Colour never carries meaning alone.** Bands use a shape and a word as well (snowflake FREEZE, magnifier REVIEW); graph nodes carry a letter; touch targets are at least 44 px.

## Limitations

Synthetic data only. No real satellite or registry feed: land is identified by parcel ids, not by geometry, so overlap means "the same parcel id", not "polygons intersect". The scan re-runs in full on each change (fine at this size). The weights are not calibrated. Single-process embedded mode serialises requests with one lock. The public demo shares one ledger between visitors: decisions persist until `POST /api/reset` rebuilds it.

## Layout

```
eco/graph.py       synthetic ledger + ground truth       eco/detect.py   queries, scan, scoring, decisions
eco/mcp_server.py  11 MCP tools (10 read, 1 note)        eco/agent.py    tool-use loop over MCP (Claude or OpenAI-compatible)
eco/server.py      JSON API + built web app              eco/envfile.py  .env loader for the server
eco/evaluate.py    precision/recall vs planted frauds    tests/          34 tests
app/               Flutter app (iOS, Android, web)       web_app/        built web app served by the API
```

## AI disclosure

This project was built with AI assistance. Claude (Anthropic) wrote most of the code, the tests, the documentation and the visual design under the author's direction, and the author reviewed and ran it. The running product uses a language model only for the Ask agent, through Gemini, the Anthropic API or another OpenAI-compatible provider chosen by whoever deploys it; `/api/health` shows which one. Detection, scoring and every decision are ordinary code over FalkorDB, with tests and an evaluation script that check behaviour.

## Links

* **Live demo:** https://ecograph-790j.onrender.com
* **Android app (APK):** [Download the latest release](https://github.com/olowolayemogoodness-crypto/ecograph/releases/latest/download/ecograph.apk)
* **Demo video:** _add your video link here_
* **Blog post:** _add your blog link here_

## License

MIT
