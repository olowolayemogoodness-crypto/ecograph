# Demo video script (about 2 minutes 45)

Record the web console in a wide browser window (1440 px or more), with the live link or `flutter run -d chrome`. Reset the demo
first (restart icon, top right). Say the lines in your own words; they are short on purpose.

| Time | On screen | Say |
|---|---|---|
| 0:00 | Title card: EcoGraph. | "A carbon credit promises one tonne kept out of the air. It only works if it is spent once. EcoGraph finds credits that were counted twice." |
| 0:12 | Console: five cases ranked, top bar numbers. | "The ledger is a FalkorDB graph: about nineteen hundred nodes. The scan found five cases, highest risk first. All data is synthetic." |
| 0:25 | Click the top case. Point at the dashed red links. | "This scheme scores 0.985. Red rings are the nodes in the problem, dashed red lines are suspicious links. One credit retired by two companies, a trading loop, and two projects on the same land." |
| 0:45 | Why tab. | "The score is not a black box. It is built from named signals: one minus the product of one minus each weight. And it says it is a rule of thumb, not a probability." |
| 0:57 | Query tab, open one query. | "This is the exact Cypher that ran in FalkorDB. Nothing here is written by the AI." |
| 1:07 | Ask tab, tap "Triage every open case". Wait for the answer (10 to 30 seconds; cut the wait when you edit). Point at the tool list, then at the "saved a note" tag. | "I ask the agent to triage the queue. It picks its own tools over MCP; here is every call it made. For each case it saves a recommendation. A note is the only thing it can write." |
| 1:37 | Rail on the left: "Agent proposes" tags. Top case: the proposal banner. | "The proposals show up on the cases. They are notes. Nothing has been frozen." |
| 1:50 | Click Freeze. Confirm sheet. Type a note. Confirm. | "The agent proposes. A person decides. This screen lists the four credits that will be frozen." |
| 2:10 | Snackbar, then the audit log (history icon). | "The decision is written back to the graph with who and when, and what the agent had proposed. A re-scan keeps it." |
| 2:25 | README or terminal: `python -m eco.evaluate`. | "I planted seven frauds and six look-alikes. It finds seven of seven with no false alarms. That proves the queries, not accuracy on a real registry." |
| 2:40 | End card: repository and live link. | "EcoGraph. FalkorDB for the graph, MCP for the tools, a human for the decision." |

Phone take (optional, 20 seconds): the same flow on the iOS simulator or an Android phone: queue, open case, Evidence tab, Freeze sheet.

Before you record: `POST /api/reset` or the reset icon (it also clears old proposals); check `/api/health` says `"agent": true`; do one dry run of "Triage every open case" first, then reset again; close notifications; export at 1080p.
