---
title: One tonne, claimed twice: I built an AI agent that finds double-counted carbon credits with a graph
tags: ai, graphdatabase, climate, python
---

# One tonne, claimed twice: I built an AI agent that finds double-counted carbon credits with a graph

*Built for Graph Hacks: Context for AI Agents (WeMakeDevs x FalkorDB), Track 1: Agents That Act on Connected Data. Every name and number from my own ledger is synthetic.*

A carbon credit is a promise that one tonne of CO2 stayed out of the air. The promise only means something if it is spent once.

In June 2025, Verra, the largest carbon standard, put an Indian cookstove project on hold after claims of double counting and ineligible credits. The developer rejects the allegations. I do not know who is right, and that is the point: the only way to find out was a manual review, one project at a time.

I wanted to see if a graph and an AI agent could do the first pass, so a human reviewer starts with a short list instead of a pile of spreadsheets. This is how I built **EcoGraph**.

## The problem is bigger than double counting

Double counting is one failure inside a larger trust problem. Researchers have measured it:

- A 2024 study in *Nature Communications* looked at 2,346 projects and found that 84% of their credits did not reflect real emission cuts.
- A study of cookstove projects found they were over-credited by 9.2 times on average.
- A 2023 investigation by the Guardian, Die Zeit and SourceMaterial found 21 rainforest projects whose credits gave no climate benefit.
- A 2025 analysis of auditors found that on 95 flagged projects, two in three auditors did not catch the flaws.

The market is small today, about 2 billion dollars in 2023, and McKinsey and Morgan Stanley project it could reach 50 billion by 2030. In June 2023 the US CFTC publicly asked for whistleblower tips on carbon fraud, including "improperly counting credits." Regulators are already worried. Most checks still look at one project at a time, and double counting lives between projects.

## Three ways to count a tonne twice

1. **Same land, two projects.** Two active projects claim the same parcel, sometimes on different registries.
2. **One credit, two buyers.** A credit is retired (claimed as an offset) by more than one company.
3. **A circle of sales.** A credit is sold from holder to holder until it comes back to one it already passed through. Nobody gains a tonne, but the trading volume looks healthy.

None of these is a row in a table. Each is a *path* through the ledger. That is why I reached for a graph database.

## The ledger as a graph

```
(Project)-[:COVERS]->(LandParcel)           (Project)-[:REGISTERED_ON]->(Registry)
(Credit)-[:ISSUED_FOR]->(Project)           (Credit)-[:RETIRED_BY {day, claim}]->(Buyer)
(Buyer)-[:SOLD_TO {credit, day, price}]->(Buyer)
```

I generated a synthetic ledger with a fixed seed: 1,900 nodes and 4,125 edges (1,634 credits, 121 buyers, 41 projects, 60 parcels and 3 registries), stored in **FalkorDB**. Then I planted 7 frauds in it and added 6 look-alike decoys that must *not* be flagged, such as neighbouring parcels and a five-hop honest resale chain.

Overlapping land is a two-hop pattern, `(p1)-[:COVERS]->(lp)<-[:COVERS]-(p2)`. A double retirement is a count over `RETIRED_BY`. The circle is the interesting one.

## The query that never finished

My first loop detector asked for any closed walk of three to six sales. On a network of 121 traders it explored every sale path there is, and it had not finished after two minutes.

The fix was one property filter. A wash trade is *one credit* going round, so every hop has to carry the same credit id:

```cypher
MATCH ()-[x:SOLD_TO]->()
WITH x.credit AS cid, count(x) AS hops WHERE hops >= 3
MATCH p = (b:Buyer)-[:SOLD_TO*3..6 {credit: cid}]->(b)
WHERE all(n IN nodes(p) WHERE b.id <= n.id)
RETURN cid, [n IN nodes(p) | n.id] AS ring, [e IN relationships(p) | e.day] AS days
```

With `{credit: cid}` the traversal only follows the sales of one credit, and the query returns in well under a second. It also fixed a correctness problem. Without the filter, three brokers who each pass a *different* credit to the next one look like a ring. That is ordinary trading, not a wash trade.

## From seven alerts to five cases

Seven findings is a bad inbox if some of them are really one story. I run a connected-components algorithm (`algo.WCC` in FalkorDB) over the findings and the projects and credits they touch. The seven findings become five cases. A double retirement, a loop and a land overlap around the same project become **one** scheme.

Each case is scored from named signals, combined as `1 - Π(1 - weight)`:

| Signal | Weight |
|---|---|
| double retirement | 0.90 |
| registry duplicate | 0.80 |
| overlap | 0.60 |
| trading loop | 0.55 |
| no audit on file | 0.15 (never raises a case alone) |

The top case has four signals pointing at one project: `1 - (0.10)(0.40)(0.45)(0.85) = 0.985`. The app says on the same screen that this is a rule of thumb, not a probability. I would rather a reviewer trust a number a little less than trust it a lot for no reason.

## The agent, and what it cannot do

The agent reaches the graph only through eleven MCP tools: the detectors, a credit tracer, the clustering, a betweenness ranking, the case list, the audit log, a read-only Cypher tool, and one tool that writes a note. Every read tool returns its rows and the exact query that produced them, so the app shows the working next to the answer.

Ask it to triage the open cases and it reads each case's signals, then records a recommendation (freeze, refer or dismiss, with a one-sentence reason) as a `Proposal` node using the eleventh tool, `propose_action`.

That is all it can write. It cannot freeze anything. A person freezes, refers or dismisses on a screen that lists exactly which credits are affected, and the decision goes back into the graph with what the agent had proposed. Afterwards you can see whether the reviewer agreed. The rule is enforced by the tool list, not by trusting a prompt, and a test checks that exactly one tool can write and that a proposal never touches a credit.

The agent runs on Gemini in my demo. The same loop works with Claude or any OpenAI-compatible model.

## The app

The interface is a Flutter app for iOS, Android and web. On a wide screen it becomes a review console, and a separate land-map dashboard plots every parcel on a world map, red where two projects claim the same land. You open it and see five cases that need a decision and 27,880 tonnes at risk. Tap *Triage every open case* and the agent ranks them. Open the top case and you see the graph with the suspicious links in red. Trace one credit from its retirement back to the land. Freeze it, and the History tab records that you agreed with the agent.

A scan of the whole ledger takes about 0.15 seconds. On the synthetic data the detectors found 7 of 7 planted frauds with 0 false alarms on the 6 decoys. Because I planted the frauds myself, this shows the queries do what they claim. It says nothing about accuracy on a real registry, whose data is much messier.

## Setbacks, and what each one taught me

**1. The query that never finished.** My first loop detector asked for any closed walk of three to six sales. On 121 traders it had not finished after two minutes. One property filter, the same credit id on every hop, made it return in under a second and fixed a correctness bug too. Lesson: let the pattern's own definition constrain the traversal.

**2. The database would not start on the server.** The embedded FalkorDB build needs a recent Linux (glibc 2.39 or newer). A Debian 12 image could not run it, so the Docker image had to move to Debian 13. Lesson: read a dependency's platform requirements before picking a base image.

**3. The free server fell asleep.** On Render's free plan the server sleeps when idle and takes up to a minute to wake. My app showed a pulsing dot and nothing else, so it looked broken. I added a clear "Connecting to the server" message and a free uptime monitor that checks the health endpoint every five minutes. My first monitor returned a 404 because I mistyped the URL. Lesson: test the boring path first.

**4. The Android app said "can't reach server".** A release build defaults to the emulator's address for the host machine, which means nothing on a real phone. The live server address has to be baked in at build time with a Dart define. Lesson: defaults that work on a laptop quietly fail in a user's hand.

**5. The map asked for an API key.** My first map tiles came from a provider that now requires a key, and the map filled with "API KEY REQUIRED" watermarks. I switched to OpenStreetMap tiles, which need none. Lesson: check what a free service really costs before you build on it.

**6. Keeping keys out of the repo.** The Gemini key lives only in a git-ignored .env file and in Render's environment settings. A publish script scans every file for key-shaped strings before each push, and it stopped me once when a test used a realistic fake key, so I made the fake one obviously fake. When a map key ended up pasted into a chat, I never put it in code, treated it as exposed and rotated it. Lesson: assume any key you have shown to anyone is public, and rotate it.

## What I learned

- A graph database earns its place when the question is about paths, not rows. Every one of the three tricks is a path.
- Keep the agent's power small and enforce it in the tool list, not in a prompt. Exactly one tool writes, and it can only write a note.
- Shipping is half the work. Deployment, keys, cold starts and a phone that cannot find the server cost me more hours than the detection logic.

## What I would do next

- Replace the synthetic ledger with public registry data.
- Scan every new issuance, sale and retirement as it happens, instead of re-running a full scan.
- Match land by geometry instead of parcel ids, so overlap means "the polygons intersect."

## Built with AI, openly

I built this with AI help. Claude wrote much of the code, tests and documentation under my direction, and I reviewed and ran it. The running product uses a language model only for the Ask agent. Detection, scoring and every decision are ordinary code over FalkorDB, covered by 34 tests.

## Try it

- Code: https://github.com/olowolayemogoodness-crypto/ecograph
- Live demo: https://ecograph-790j.onrender.com
- Land map dashboard: https://ecograph-790j.onrender.com/dashboard
- Android app: https://github.com/olowolayemogoodness-crypto/ecograph/releases/latest/download/ecograph.apk
- Demo video: https://youtu.be/razXGl26_0A

The README has a five-step setup. All data is synthetic, and nothing here accuses a real company.

*Sources: Probst et al., Nature Communications, 2024. Gill-Wiehl et al., Nature Sustainability, 2024. Guardian, Die Zeit and SourceMaterial, January 2023. Coglianese and Giles, SSRN, 2025. Phillips & Cohen on the CFTC, June 2023 (market figures from McKinsey and Morgan Stanley). Carbon Pulse, 12 June and 7 July 2025.*
