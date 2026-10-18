"""MCP server: the carbon ledger graph exposed as tools an agent can choose between.

    python -m eco.mcp_server        # stdio, for Claude Desktop / any MCP client (set FALKORDB_HOST to use a server)

Every result carries a `_trace` (the exact Cypher that produced it) so the app can show the working.
Ten tools only read. The eleventh, propose_action, writes one thing: a Proposal note on a case. It freezes nothing
and closes nothing; freezing, referring and dismissing stay with a person (see eco.detect.decide).
"""
import os

from mcp.server.mcpserver import MCPServer

from eco import detect as D, graph

INSTRUCTIONS = (
    "Tools over a FalkorDB graph of a synthetic voluntary carbon-credit ledger (projects, land parcels, registries, "
    "credits, buyers, audit reports). Start with list_cases for what the scan already found and how it scored. "
    "Use the find_* detectors to check one fraud pattern, trace_credit_upstream to follow one credit from retirement "
    "back to the land, cluster_suspicious to see whether findings belong to one scheme, rank_intermediaries for "
    "network position (which proves nothing alone), list_actions for what a person already decided. "
    "Use run_cypher only when no other tool fits. propose_action records your recommendation on a case for a person "
    "to accept or override; it is the only tool that writes, and it cannot freeze, refer or dismiss anything."
)


def build_server(g, cases_fn=None) -> MCPServer:
    """`cases_fn()` returns the cached scan result; the standalone server scans once at start-up."""
    if cases_fn is None:
        cache = {}
        cases_fn = lambda: cache.setdefault("scan", D.scan(g))
    mcp = MCPServer("ecograph", instructions=INSTRUCTIONS)

    @mcp.tool()
    def list_cases() -> dict:
        """Fraud cases from the latest scan, highest risk first. Each has a score from 0 to 1 built from
        named signals (so you can explain it), the projects involved, credits at risk, the suggested action
        (freeze, refer or watch), its status (open, or what a person decided) and any proposal still waiting.
        Call this first."""
        scan = cases_fn()
        rows = D._rows(g, "MATCH (f:Finding) RETURN f.id, f.type, f.weight ORDER BY f.weight DESC")
        keep = ("id", "title", "score", "band", "suggested", "types", "projects", "credits_at_risk", "tonnes_at_risk", "summary")
        decided, waiting = D.decisions(g), D.proposals(g)
        return {"cases": [{**{k: c[k] for k in keep}, "status": (decided.get(c["id"]) or {}).get("status") or "open",
                           "pending_proposal": (waiting.get(c["id"]) or {}).get("action"),
                           "signals": [{"signal": s["signal"], "weight": s["weight"]} for s in c["signals"]]}
                          for c in scan["cases"]],
                "note": "Scores are a documented rule of thumb (noisy-or of signal weights), not a calibrated probability.",
                "_trace": D._trace("list_cases", "MATCH (f:Finding) RETURN f.id, f.type, f.weight ORDER BY f.weight DESC", detail=f"{len(rows)} finding(s) grouped into {len(scan['cases'])} case(s)")}

    @mcp.tool()
    def find_overlapping_claims() -> dict:
        """Pairs of active projects that claim some of the same land parcels (with their registries). Exact copies
        of one project on two registries are reported by find_registry_duplicates instead."""
        return D.find_overlapping_claims(g)

    @mcp.tool()
    def find_registry_duplicates() -> dict:
        """Projects on different registries that cover exactly the same land, i.e. one project listed twice."""
        return D.find_registry_duplicates(g)

    @mcp.tool()
    def find_double_retirements() -> dict:
        """Credits that were retired (claimed as an offset) by more than one buyer."""
        return D.find_double_retirements(g)

    @mcp.tool()
    def find_trading_loops() -> dict:
        """Credits sold around a circle of 3 to 6 holders until they return to an earlier holder (wash trading).
        Two parties swapping different credits is not a loop and is not returned."""
        return D.find_trading_loops(g)

    @mcp.tool()
    def trace_credit_upstream(credit_id: str) -> dict:
        """Follow one credit from its retirement back through every sale to the developer, the project, its
        registry, its audit report and the land, listing red flags on the way (hops counted)."""
        return D.trace_credit_upstream(g, credit_id)

    @mcp.tool()
    def cluster_suspicious() -> dict:
        """Group findings that share a project or credit using a graph connected-components algorithm (WCC).
        One cluster with several findings suggests one scheme rather than coincidences."""
        cases_fn()
        return D.cluster_suspicious(g)

    @mcp.tool()
    def rank_intermediaries(k: int = 8) -> dict:
        """Top k buyers by betweenness centrality in the sale network, marked if they appear in a finding.
        Position in the network is context, not proof: busy honest brokers rank high too."""
        return D.rank_intermediaries(g, k)

    @mcp.tool()
    def list_actions() -> dict:
        """Freezes, referrals and dismissals a person already recorded. Check before recommending something already done."""
        return D.list_actions(g)

    @mcp.tool()
    def run_cypher(query: str) -> dict:
        """Read-only Cypher for questions no other tool answers. Labels: Project, LandParcel, Registry, Credit,
        Buyer, AuditReport, Finding, Case, AuditLog, Proposal. Relationships: COVERS, REGISTERED_ON, VERIFIED_BY,
        DEVELOPED_BY, ISSUED_FOR, RETIRED_BY, SOLD_TO (credit, day, price), INVOLVES, FLAGS, RECORDS, ABOUT.
        Writes are rejected."""
        return D.run_cypher(g, query)

    @mcp.tool()
    def propose_action(case_id: str, action: str, rationale: str) -> dict:
        """Record your recommendation on one open case so the reviewer sees it on the case and in the queue.
        action is freeze, refer or dismiss. rationale is one sentence that names the signals behind it. This is
        the only tool that writes, and it writes a note: it freezes nothing, refers nothing and closes nothing; a
        person still decides in the app. Look at the case first, propose at most once per case, and do not
        propose on a case that is already decided."""
        case = next((c for c in cases_fn()["cases"] if c["id"] == case_id), None)
        if not case:
            return {"error": f"No such case: {case_id}. Call list_cases for the ids."}
        status = (D.decisions(g).get(case_id) or {}).get("status")
        if status:
            return {"error": f"{case_id} is already {status}: a person decided, so there is nothing to propose."}
        try:
            return D.propose(g, case, action, rationale)
        except ValueError as e:
            return {"error": str(e)}

    return mcp


if __name__ == "__main__":
    build_server(graph.open_graph(fresh=not os.environ.get("FALKORDB_HOST"))).run()
