# Submission text for the WeMakeDevs form

Copy each block into the matching field. Replace the `<...>` links last. Everything below is true of the code in this repo; if you change the project, change the text.

## Name

EcoGraph

## Track

Track 1: Agents That Act on Connected Data (the only track entered)

## One line

An agent that finds carbon credits counted twice by asking a FalkorDB graph questions about paths, proposes what to do, and leaves every freeze to a person.

## Short description (about 60 words)

A carbon credit only works if it is spent once. EcoGraph stores a carbon-credit ledger in FalkorDB and finds the paths that break that promise: the same land under two projects, one credit retired twice, a credit sold in a circle. An AI agent reaches the graph only through MCP tools and can leave a recommendation. A person decides.

## Long description

**The problem.** The voluntary carbon market loses trust when one tonne is claimed twice. The ways to do that are paths, not rows: two projects covering the same parcel, a credit retired by two buyers, a credit sold around a circle of holders to fake volume.

**What EcoGraph does.** It keeps the ledger as a graph in FalkorDB (credits, buyers, projects, land parcels, registries, audit reports) and runs four detectors written in plain OpenCypher. Findings are written back as nodes, clustered with `algo.WCC` so findings that share a project or credit become one scheme, and scored with named signals combined as `1 - Π(1 - weight)`. A reviewer sees the evidence as a subgraph with the suspicious links marked, the signals behind the score, and the exact Cypher that ran.

**The agent.** A language model (Claude, or Gemini or Groq through an OpenAI-compatible API) is given 11 MCP tools: 10 that only read the graph, and `propose_action`, which writes a `Proposal` node on one open case. Asked to "triage every open case", it reads each case's signals and records a recommendation with a one-sentence reason. It cannot freeze, refer or dismiss anything.

**The human.** A person confirms a freeze, a referral or a dismissal in the Flutter app (iOS, Android, web). The decision is written back to the graph as `Case`, `AuditLog` and `Credit.frozen`, and the audit log records whether the person agreed with the agent.

**Measured on the synthetic ledger** (1,893 nodes and 4,108 edges, fixed seed): all 7 planted frauds found, no alarm on 6 look-alike decoys, a full scan in about 0.1 s, 34 automated tests. The frauds are planted by the same code that checks them, so this shows the queries behave as described and says nothing about accuracy on a real registry. Land is matched by parcel id, not geometry, and the score weights are a documented judgement, not fitted to data.

## How FalkorDB is used (and why the product does not work without it)

- The ledger is a property graph; every detector is a Cypher pattern over it (`COVERS` two-hop overlap, `RETIRED_BY` counts, a variable-length `SOLD_TO*3..6` path filtered on the credit id for sales circles, `OPTIONAL MATCH` for the upstream trace).
- `algo.WCC` groups findings into cases. `algo.betweenness` ranks intermediaries as context (it never enters the score).
- The graph is also the system's memory: findings, agent proposals, human decisions and the audit log are nodes and relationships in the same graph, so they survive a re-scan.
- The agent's tools are graph queries, and the app shows each one's Cypher.
- Runs with the embedded `falkordblite` or a FalkorDB server (`FALKORDB_HOST`).

## Built with

FalkorDB, OpenCypher, `algo.WCC`, `algo.betweenness`, the MCP Python SDK, Claude and Gemini, a Python standard-library HTTP API, Flutter (iOS, Android, web), Docker, Render.

## Links

- Source code: `<GitHub repo URL>`
- Live demo: `<Render URL>`
- Demo video: https://youtu.be/razXGl26_0A
- Blog post: `<blog URL>`
- Slides and APK (optional): `<Google Drive folder URL>`

## Data

All data is synthetic. Registries, projects and companies are invented. Nothing accuses a real party.

## AI disclosure (edit this so it is true of you)

This project was built with AI assistance. Claude (Anthropic) wrote most of the code, the tests, the documentation and the visual design under my direction. I `<chose the problem and the graph model, reviewed the queries, ran the tests and the evaluation, and tried the app and the agent myself>`. The running product uses a language model only for the Ask agent. Detection, scoring and every decision are ordinary code over FalkorDB, with tests and an evaluation script that check behaviour. I can explain the graph model, the circle-of-sales query and the scoring rule.
