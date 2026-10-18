# EcoGraph API contract (for the Flutter app)

Base URL: your deployed backend, for example `https://ecograph-api.example.com`. JSON in, JSON out.
If the server has `ECO_TOKEN` set, send `Authorization: Bearer <token>` on every call except `/api/health`.
All data is synthetic. The Claude key never goes in the app.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | `{ok, cases, agent, provider, model, database}`. `agent` is false when the server has no model key; `provider` and `model` say which one answers Ask. |
| GET | `/api/overview` | `{nodes, edges, by_label, cases, open, freeze_suggested, tonnes_at_risk, synthetic}` for the home header. |
| GET | `/api/cases` | `{cases: [Case]}` ranked by score, highest first. |
| GET | `/api/cases/{id}` | `CaseDetail` (below). |
| POST | `/api/cases/{id}/decision` | Body `{action: "freeze"\|"refer"\|"dismiss", note?}`. Returns `{case, status, credits_frozen, log, at, proposed}` where `case` is a fresh `CaseDetail` and `proposed` is what the agent had proposed (`""` if nothing). `409` if already decided, `400` for a bad action. This is the only call that can freeze a credit. |
| GET | `/api/credits/{id}` | Upstream trace of one credit (below). |
| GET | `/api/actions` | `{actions: [{log, case, action, at, credits_frozen, by, note, proposed}], pending_proposals: [{case, action, rationale, at}]}`: the audit log, newest first, and the agent's proposals that no person has settled yet. |
| POST | `/api/ask` | Body `{question, case_id?}`. Returns `{answer, calls, tools_available}`. `503` with `unavailable: true` if no model key, `429` if rate limited. Slow: 3 to 15 seconds. The agent may save a proposal while answering (a `propose_action` entry in `calls`); reload the case to see it. |
| POST | `/api/reset` | Rebuilds the synthetic ledger (use before recording the demo). |

Errors are `{error: "message"}` with the HTTP code.

## Case (queue row)
```json
{ "id": "CASE-3774F", "title": "Linked scheme around P-07, P-19", "score": 0.985,
  "band": "freeze",            // freeze (>= 0.85) | review (>= 0.50) | watch
  "suggested": "freeze",       // freeze | refer | watch
  "types": ["double_retirement", "loop", "overlap"],
  "projects": ["P-07", "P-19"], "credits_at_risk": 4, "tonnes_at_risk": 1140, "credits_frozen": 0,
  "summary": "CR-00694 (190 t, P-19) was retired by Corporate 14 and Corporate 31. ...",
  "status": "open",            // open | frozen | referred | dismissed
  "note": null, "decided_at": null,
  "proposal": null }           // or {action, rationale, by: "agent", at}: the agent's note, only while the case is open
```
`types` values: `double_retirement`, `loop`, `overlap`, `registry_duplicate`.

## CaseDetail = Case plus
```json
{ "findings": [{ "id": "loop:BR-02|BR-05|CO-08", "type": "loop", "title": "...", "summary": "...", "weight": 0.55 }],
  "signals":  [{ "signal": "double_retirement", "weight": 0.9, "why": "The same credit was retired by two different buyers.", "finding": "double_retirement:CR-00694" }],
  "evidence": { "nodes": [{ "id": "P-19", "kind": "project", "label": "P-19", "sub": "", "flag": true, "x": 0.54, "y": 0.58 }],
                "edges": [{ "a": "CR-00694", "b": "P-19", "rel": "ISSUED_FOR", "label": "optional", "flag": false }] },
  "at_risk_ids": ["CR-00691", "CR-00692", "CR-00693", "CR-00694"],
  "trace": [{ "tool": "find_double_retirements", "cypher": "MATCH ...", "params": {}, "detail": "2 credit(s) retired twice" }],
  "how_to_read": "Score = 1 - product of (1 - weight) ..." }
```
* `evidence` is the subgraph to draw. `x` and `y` are 0..1 positions already laid out, so a `CustomPainter` can scale them to the canvas. `flag: true` marks the nodes that are part of the problem, and on an edge it marks a suspicious link (draw it dashed and red).
* `at_risk_ids` are the credits a freeze would mark (at most 60 are listed; `credits_at_risk` is the full count).
* `kind`: `project`, `parcel`, `registry`, `credit`, `buyer`. `rel`: `COVERS`, `REGISTERED_ON`, `ISSUED_FOR`, `RETIRED_BY`, `SOLD_TO`, `SOLD_VIA`.
* `signals` explain the score line by line. Show them as the "why".
* `trace` is the exact Cypher behind the case, for the "Show the query" tab.

## Credit trace (`GET /api/credits/{id}`)
```json
{ "credit": "CR-00694", "tonnes": 190, "status": "RETIRED", "hops": 5,
  "project": { "id": "P-19", "name": "Cookstove P-19", "country": "Ghana", "parcels": ["LP-027", "LP-011"],
               "registry": "TerraRegistry", "audit": null, "developer": "DEV-19" },
  "sales": [{ "from": "DEV-19", "to": "BR-07", "day": 30 }],
  "retired": [{ "buyer": "CO-14", "name": "Corporate 14", "day": 40, "claim": "CLM-4410" }],
  "rival_claims": [{ "project": "P-07", "parcel": "LP-011" }],
  "flags": ["Retired more than once.", "Its land is also claimed by P-07."] }
```

## Ask (`POST /api/ask`)
`calls` lists each tool the model chose: `[{tool, input, detail, cypher}]`. Show them under the answer so the reader sees what it looked at.
A `propose_action` call (`input: {case_id, action, rationale}`) means the agent saved a recommendation. It is a note: it appears as `proposal` on the case and under `pending_proposals`, and nothing is frozen, referred or dismissed until a person calls `POST /api/cases/{id}/decision`. The decision then marks the proposal `accepted` (same action) or `overridden`, and the audit entry keeps it in `proposed`.
