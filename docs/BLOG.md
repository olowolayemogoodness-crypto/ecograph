# One tonne, claimed twice: catching double-counted carbon credits with a graph

*Built for Graph Hacks 2026 (FalkorDB x WeMakeDevs), Track 1: Agents That Act on Connected Data. Every name and number below comes from a synthetic ledger.*

A carbon credit is a promise that one tonne of CO2 stayed out of the air. The promise only means something if it is spent once. In the ledger I built for this project, credit CR-00694 (190 tonnes, from project P-19) was retired by two different companies. Two companies, one tonne, both claiming the offset.

That one you can find with a GROUP BY. The other ways of counting a tonne twice are harder, and they are the reason I reached for a graph.

## Three ways to count a tonne twice

1. **Same land, two projects.** Two active projects claim the same parcel, sometimes on different registries. P-07 and P-19 both cover parcel LP-011.
2. **One credit, two buyers.** A credit is retired (claimed as an offset) by more than one company.
3. **A circle of sales.** A credit is sold from holder to holder until it comes back to one it already passed through. Nobody gains a tonne; the trading volume looks healthy.

None of these is a row. Each is a *path* through the ledger, and the question is whether the path has a shape it should not have.

## The ledger as a graph

```
(Project)-[:COVERS]->(LandParcel)           (Project)-[:REGISTERED_ON]->(Registry)
(Credit)-[:ISSUED_FOR]->(Project)           (Credit)-[:RETIRED_BY {day, claim}]->(Buyer)
(Buyer)-[:SOLD_TO {credit, day, price}]->(Buyer)
```

It is synthetic, generated with a fixed seed: 1,900 nodes and 4,125 edges (1,634 credits, 121 buyers, 41 projects, 60 parcels, 3 registries), stored in FalkorDB. Overlapping land is a two-hop pattern, `(p1)-[:COVERS]->(lp)<-[:COVERS]-(p2)`. Double retirement is a count over `RETIRED_BY`. The circle is the interesting one.

## The query that did not finish

My first loop detector asked for any closed walk of three to six sales. On a network with a hundred and twenty traders it explored every sale path there is, and it had not finished after two minutes.

The fix was one property filter. A wash trade is *one credit* going round, so every hop has to carry the same credit id:

```cypher
MATCH ()-[x:SOLD_TO]->()
WITH x.credit AS cid, count(x) AS hops WHERE hops >= 3
MATCH p = (b:Buyer)-[:SOLD_TO*3..6 {credit: cid}]->(b)
WHERE all(n IN nodes(p) WHERE b.id <= n.id)         -- report each circle once
RETURN cid, [n IN nodes(p) | n.id] AS ring, [e IN relationships(p) | e.day] AS days
```

With `{credit: cid}` the traversal only follows the sales of one credit, and the query returns in tens of milliseconds. It also fixed a correctness problem. Without the filter, three brokers who each pass a *different* credit to the next one form a ring that looks like a circle. That is ordinary trading. A wash trade is one credit coming back to a holder it already passed through, which is exactly what the filter says.

## From alerts to cases

Seven findings is a bad inbox if they are really one story. I run a connected-components algorithm (`algo.WCC` in FalkorDB) over the findings and the projects and credits they touch. The seven findings collapse into five cases. The double retirement, the loop and the overlap around P-07 and P-19 become **one** scheme, because they share a project.

Each case gets a score from named signals, combined as `1 - Π(1 - weight)`:

| Signal | Weight |
|---|---|
| double retirement | 0.90 |
| registry duplicate | 0.80 |
| overlap | 0.60 |
| trading loop | 0.55 |
| no audit on file | 0.15 (corroborates only) |

The scheme around P-19 has four of them: `1 - (0.10)(0.40)(0.45)(0.85) = 0.985`. The app says, on the same screen, that this is a rule of thumb and not a probability. I would rather a reviewer distrust a number a little than trust it a lot for no reason.

## The agent, and what it cannot do

The agent reaches the graph only through eleven MCP tools: the four detectors, a credit tracer, the clustering, a betweenness ranking, the case list, the audit log, a read-only Cypher escape hatch (`ro_query` rejects writes), and one tool that writes a note. Every read tool returns its rows and the exact query that produced them, so the app can show the working next to the answer.

```python
@mcp.tool()
def find_double_retirements() -> dict:
    """Credits that were retired (claimed as an offset) by more than one buyer."""
    return D.find_double_retirements(g)
```

The eleventh tool is the one that lets the agent act. Ask it to triage the open cases and it reads each case's signals, then records a recommendation (freeze, refer or dismiss, with a one-sentence reason that names the signals) as a `Proposal` node linked to the case's projects:

```python
@mcp.tool()
def propose_action(case_id: str, action: str, rationale: str) -> dict:
    """Record your recommendation on one open case so the reviewer sees it on the case and in the queue..."""
```

A proposal is all it can write. It shows up as a note on the case and in the queue, and it freezes nothing. That is the design, not an omission. A person freezes, refers or dismisses, on a screen that lists exactly which credits will be frozen, and the decision is written back into the graph as a `Case`, an `AuditLog` node and `FLAGS` edges. The audit entry also keeps what the agent had proposed, so you can see afterwards whether the reviewer agreed. A re-scan keeps all of it, so the graph is also the system's memory. A test checks that exactly one tool can write and that a proposal never touches a credit. In this prototype a freeze is a flag in the graph; connecting it to a registry is the production step.

The same loop runs on Claude or on any OpenAI-compatible model, so a free Gemini or Groq key is enough to try it. It is tested against scripted models, including a mock HTTP provider.

## Is it any good?

`python -m eco.evaluate` plants seven frauds (two overlaps, one registry duplicate, two double retirements, two loops) next to six look-alikes: neighbouring parcels, an ended project followed by a new one on the same land, an honest five-hop resale chain, two brokers swapping different credits, a large honest buyer, and projects that simply have no audit report. It finds 7 of 7 and raises 0 false alarms.

That number needs its caveat. The frauds are planted by the same code that checks them, so this proves the queries do what they claim and stay quiet on the decoys. It says nothing about a real registry, where data is messier and "the same land" is a polygon, not a parcel id. In this prototype, overlap means the same parcel id.

## What I would do next

* Real geometry, so overlap means polygons that intersect.
* Fit the weights on labelled cases instead of choosing them by judgement.
* Make a freeze a real action against a registry API, behind the same human confirmation.

## Try it

The app is one Flutter codebase for iOS, Android and web. On a phone it is a queue and a case with Evidence, Why, Query and Ask tabs. On a wide screen it is a three-pane console. Everything, including the Cypher, is in the repository.

* Code: _repository link_
* Live demo: _link_
* Video: _link_
