"""The graph queries and algorithms the agent uses, plus the scan, scoring and case logic.

Every detector is plain OpenCypher (or a FalkorDB graph algorithm) run against the ledger, and returns
the rows together with a `_trace` entry holding the exact query, so the app can show its working.

Detectors:     find_overlapping_claims, find_registry_duplicates, find_double_retirements, find_trading_loops
Investigation: trace_credit_upstream, rank_intermediaries (algo.betweenness), cluster_suspicious (algo.WCC)
Cases:         scan() writes (:Finding)-[:INVOLVES]->(...) and groups findings into cases with an explainable score.
Actions:       decide() is the only write a person can trigger. propose() is the only write the agent has, and it is
               only a note attached to a case: it freezes nothing, refers nothing and closes nothing.
"""
import datetime
import hashlib
import math
import random

# ---- Cypher ---------------------------------------------------------------------------------------------
Q_PAIRS = """MATCH (p1:Project)-[:COVERS]->(lp:LandParcel)<-[:COVERS]-(p2:Project)
WHERE p1.id < p2.id AND p1.status = 'ACTIVE' AND p2.status = 'ACTIVE'
MATCH (p1)-[:REGISTERED_ON]->(r1:Registry), (p2)-[:REGISTERED_ON]->(r2:Registry)
WITH p1, p2, r1, r2, collect(lp.id) AS shared
MATCH (p1)-[:COVERS]->(a:LandParcel)
WITH p1, p2, r1, r2, shared, count(a) AS n1
MATCH (p2)-[:COVERS]->(b:LandParcel)
RETURN p1.id, p2.id, r1.id, r2.id, shared, n1, count(b) AS n2"""

Q_DOUBLE_RETIRE = """MATCH (c:Credit)-[r:RETIRED_BY]->(b:Buyer)
WITH c, collect({buyer: b.id, name: b.name, day: r.day, claim: r.claim}) AS claims
WHERE size(claims) > 1
MATCH (c)-[:ISSUED_FOR]->(p:Project)
RETURN c.id, c.tonnes, p.id, claims"""

# Only a credit that changes hands three or more times can come back to a holder, so the traversal is
# restricted to those and follows that one credit's sales (the {credit: cid} filter keeps it fast).
Q_LOOPS = """MATCH ()-[x:SOLD_TO]->()
WITH x.credit AS cid, count(x) AS hops WHERE hops >= 3
MATCH p = (b:Buyer)-[:SOLD_TO*3..6 {credit: cid}]->(b)
WHERE all(n IN nodes(p) WHERE b.id <= n.id)
RETURN cid, [n IN nodes(p) | n.id] AS ring, [e IN relationships(p) | e.day] AS days"""

Q_TRADES = """MATCH (a:Buyer)-[x:SOLD_TO]->(b:Buyer) WHERE x.credit IN $ids
RETURN x.credit, a.id, a.kind, b.id, x.day ORDER BY x.day"""

Q_UPSTREAM_HEAD = """MATCH (c:Credit {id: $id})-[:ISSUED_FOR]->(p:Project)
OPTIONAL MATCH (p)-[:COVERS]->(lp:LandParcel)
OPTIONAL MATCH (p)-[:REGISTERED_ON]->(r:Registry)
OPTIONAL MATCH (p)-[:VERIFIED_BY]->(a:AuditReport)
OPTIONAL MATCH (p)-[:DEVELOPED_BY]->(d:Buyer)
RETURN c.id, c.tonnes, c.status, p.id, p.name, p.country, collect(DISTINCT lp.id), r.name, a.auditor, a.date, d.id"""

Q_UPSTREAM_RIVALS = """MATCH (c:Credit {id: $id})-[:ISSUED_FOR]->(p:Project)-[:COVERS]->(lp:LandParcel)<-[:COVERS]-(q:Project)
WHERE q <> p AND q.status = 'ACTIVE'
RETURN q.id, lp.id"""

Q_RETIRED = "MATCH (c:Credit {id: $id})-[r:RETIRED_BY]->(b:Buyer) RETURN b.id, b.name, r.day, r.claim"

Q_BETWEENNESS = """CALL algo.betweenness({nodeLabels: ['Buyer'], relationshipTypes: ['SOLD_TO']}) YIELD node, score
RETURN node.id, node.name, node.kind, score ORDER BY score DESC LIMIT $k"""

Q_WCC = """CALL algo.WCC({nodeLabels: ['Finding', 'Project', 'Credit'], relationshipTypes: ['INVOLVES']}) YIELD node, componentId
RETURN node.id, labels(node), componentId"""

Q_UNAUDITED = "MATCH (p:Project) WHERE p.status = 'ACTIVE' AND NOT (p)-[:VERIFIED_BY]->(:AuditReport) RETURN p.id"

Q_AT_RISK = """MATCH (c:Credit)-[:ISSUED_FOR]->(p:Project) WHERE p.id IN $pids AND c.status = 'ACTIVE'
RETURN c.id, c.tonnes, c.frozen"""

Q_CREDITS = "MATCH (c:Credit) WHERE c.id IN $ids RETURN c.id, c.tonnes, c.frozen"

Q_OVERVIEW = """MATCH (n) RETURN labels(n)[0], count(n)"""

WEIGHTS = {"double_retirement": 0.90, "registry_duplicate": 0.80, "overlap": 0.60, "loop": 0.55, "no_audit": 0.15}
WHY = {
    "double_retirement": "The same credit was retired by two different buyers.",
    "registry_duplicate": "The same land is registered as a project on two registries.",
    "overlap": "Two active projects claim the same land.",
    "loop": "One credit was sold around a circle and came back to a holder it had already passed through.",
    "no_audit": "No audit report is on file for a project in this case.",
}
FREEZE_AT, REVIEW_AT = 0.85, 0.50
ACTIONS = ("freeze", "refer", "dismiss")

Q_PROPOSE = ("CREATE (:Proposal {id: $id, case: $c, action: $a, rationale: $r, by: 'agent', at: $t, "
             "status: 'pending', score: $s})")
Q_ABOUT = "UNWIND $ps AS x MATCH (p:Proposal {id: $id}), (j:Project {id: x}) CREATE (p)-[:ABOUT]->(j)"


def _now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def _trace(tool, cypher, params=None, detail=""):
    return {"tool": tool, "cypher": cypher, "params": params or {}, "detail": detail}


def _rows(g, q, params=None):
    return g.ro_query(q, params).result_set if params is not None else g.ro_query(q).result_set


def _clean(v):
    """FalkorDB returns maps as OrderedDicts; make rows JSON friendly."""
    if isinstance(v, dict):
        return {k: _clean(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [_clean(x) for x in v]
    return v


# ---- detectors ---------------------------------------------------------------------------------------
def _pairs(g):
    out = []
    for p1, p2, r1, r2, shared, n1, n2 in _rows(g, Q_PAIRS):
        same_land = len(shared) == n1 == n2
        out.append({"a": p1, "b": p2, "reg_a": r1, "reg_b": r2, "shared": shared, "same_land": same_land})
    return out


def find_overlapping_claims(g):
    """Pairs of active projects that claim some of the same land (excluding exact duplicates across registries)."""
    rows = [p for p in _pairs(g) if not (p["same_land"] and p["reg_a"] != p["reg_b"])]
    return {"overlaps": rows, "count": len(rows),
            "_trace": _trace("find_overlapping_claims", Q_PAIRS, detail=f"{len(rows)} overlapping pair(s)")}


def find_registry_duplicates(g):
    """Projects on different registries that cover exactly the same land."""
    rows = [p for p in _pairs(g) if p["same_land"] and p["reg_a"] != p["reg_b"]]
    return {"duplicates": rows, "count": len(rows),
            "_trace": _trace("find_registry_duplicates", Q_PAIRS, detail=f"{len(rows)} duplicate listing(s)")}


def find_double_retirements(g):
    """Credits retired by more than one buyer."""
    rows = [{"credit": c, "tonnes": t, "project": p, "claims": _clean(cl)} for c, t, p, cl in _rows(g, Q_DOUBLE_RETIRE)]
    return {"double_retirements": rows, "count": len(rows),
            "_trace": _trace("find_double_retirements", Q_DOUBLE_RETIRE, detail=f"{len(rows)} credit(s) retired twice")}


def find_trading_loops(g):
    """Credits sold around a circle of 3 to 6 holders. A swap of two different credits is not a loop."""
    raw = _rows(g, Q_LOOPS)
    loops = {}
    for cid, ring, days in raw:
        holders = ring[:-1]
        key = "|".join(sorted(holders))
        L = loops.setdefault(key, {"holders": holders, "credits": [], "days": {}})
        L["credits"].append(cid)
        L["days"][cid] = days
    rows = [{"key": k, "holders": v["holders"], "credits": sorted(v["credits"]), "days": v["days"]} for k, v in loops.items()]
    return {"loops": rows, "count": len(rows),
            "_trace": _trace("find_trading_loops", Q_LOOPS, detail=f"{len(rows)} circle(s), {sum(len(r['credits']) for r in rows)} credit(s)")}


def trace_credit_upstream(g, credit_id):
    """Walk from a credit back to the land: retirement, every sale, the developer, the project, its registry, audit and parcels."""
    head = _rows(g, Q_UPSTREAM_HEAD, {"id": credit_id})
    if not head:
        return {"error": f"No credit {credit_id}."}
    cid, tonnes, status, pid, pname, country, parcels, registry, auditor, adate, dev = head[0]
    sales = [{"from": a, "to": b, "day": d} for _, a, _, b, d in _rows(g, Q_TRADES, {"ids": [credit_id]})]
    retired = [{"buyer": b, "name": n, "day": d, "claim": cl} for b, n, d, cl in _rows(g, Q_RETIRED, {"id": credit_id})]
    rivals = [{"project": q, "parcel": lp} for q, lp in _rows(g, Q_UPSTREAM_RIVALS, {"id": credit_id})]
    flags = []
    if len(retired) > 1:
        flags.append("Retired more than once.")
    if rivals:
        flags.append("Its land is also claimed by " + ", ".join(sorted({r["project"] for r in rivals})) + ".")
    if not auditor:
        flags.append("No audit report on file for the project.")
    holders = [dev] + [s["to"] for s in sales]
    if len(set(holders)) < len(holders):
        flags.append("A holder appears twice in the chain of sales.")
    hops = len(sales) + (1 if retired else 0) + 2          # sales, retirement, project->developer, project->land
    return {"credit": cid, "tonnes": tonnes, "status": status, "project": {"id": pid, "name": pname, "country": country,
            "parcels": parcels, "registry": registry, "audit": ({"auditor": auditor, "date": adate} if auditor else None),
            "developer": dev}, "sales": sales, "retired": retired, "rival_claims": rivals, "flags": flags, "hops": hops,
            "_trace": [_trace("trace_credit_upstream", Q_UPSTREAM_HEAD, {"id": credit_id}, f"{hops} hops from retirement to land"),
                       _trace("trace_credit_upstream", Q_TRADES.replace("x.credit IN $ids", "x.credit IN [$id]"), {"id": credit_id}, f"{len(sales)} sale(s)")]}


def rank_intermediaries(g, k=8):
    """Betweenness centrality over the sale network: which buyers sit on the most trade routes. Each is joined
    to the findings it appears in, so a busy honest broker can be told apart from one in a loop."""
    rows = _rows(g, Q_BETWEENNESS, {"k": int(k)})
    flagged = {h for r in find_trading_loops(g)["loops"] for h in r["holders"]}
    flagged |= {c["buyer"] for r in find_double_retirements(g)["double_retirements"] for c in r["claims"]}
    return {"ranking": [{"buyer": b, "name": n, "kind": kd, "betweenness": round(float(s), 1), "in_a_finding": b in flagged}
                        for b, n, kd, s in rows],
            "note": "Betweenness measures position in the network, not wrongdoing. A high score alone proves nothing.",
            "_trace": _trace("rank_intermediaries", Q_BETWEENNESS, {"k": int(k)}, f"top {len(rows)} by betweenness")}


def cluster_suspicious(g):
    """Weakly connected components over (Finding)-[:INVOLVES]->(Project|Credit): findings that share a project or
    credit fall in one cluster, i.e. one scheme rather than coincidences. Needs scan() to have run."""
    comp = {}
    for nid, labels, cc in _rows(g, Q_WCC):
        comp.setdefault(cc, {"findings": [], "projects": [], "credits": []})
        key = "findings" if "Finding" in labels else "projects" if "Project" in labels else "credits"
        comp[cc][key].append(nid)
    clusters = [{"findings": sorted(v["findings"]), "projects": sorted(v["projects"]), "credits": len(v["credits"])}
                for v in comp.values() if v["findings"]]
    clusters.sort(key=lambda c: (-len(c["findings"]), c["findings"][0]))
    return {"clusters": clusters, "count": len(clusters),
            "_trace": _trace("cluster_suspicious", Q_WCC, detail=f"{len(clusters)} cluster(s), largest has {max((len(c['findings']) for c in clusters), default=0)} finding(s)")}


# ---- scan: findings -> clusters -> cases ---------------------------------------------------------------
def _fid(ftype, key):
    return f"{ftype}:{key}"


def _noisy_or(ws):
    p = 1.0
    for w in ws:
        p *= 1 - w
    return round(1 - p, 3)


def _layout(nodes, edges, seed=3, iters=220):
    """Small deterministic spring layout, positions scaled to 0..1, so the app can draw the evidence without a graph library."""
    rnd = random.Random(seed)
    ids = [n["id"] for n in nodes]
    pos = {i: [rnd.random(), rnd.random()] for i in ids}
    k = math.sqrt(1.0 / max(len(ids), 1))
    for t in range(iters):
        disp = {i: [0.0, 0.0] for i in ids}
        for i in ids:
            for j in ids:
                if i < j:
                    dx, dy = pos[i][0] - pos[j][0], pos[i][1] - pos[j][1]
                    d = math.hypot(dx, dy) or 0.01
                    f = k * k / d
                    for who, s in ((i, 1), (j, -1)):
                        disp[who][0] += s * dx / d * f
                        disp[who][1] += s * dy / d * f
        for e in edges:
            if e["a"] in pos and e["b"] in pos:
                dx, dy = pos[e["a"]][0] - pos[e["b"]][0], pos[e["a"]][1] - pos[e["b"]][1]
                d = math.hypot(dx, dy) or 0.01
                f = d * d / k
                for who, s in ((e["a"], -1), (e["b"], 1)):
                    disp[who][0] += s * dx / d * f
                    disp[who][1] += s * dy / d * f
        temp = 0.1 * (1 - t / iters) + 0.002
        for i in ids:
            dl = math.hypot(*disp[i]) or 0.01
            pos[i][0] += disp[i][0] / dl * min(dl, temp)
            pos[i][1] += disp[i][1] / dl * min(dl, temp)
    _normalise(pos)
    _separate(pos)
    for n in nodes:
        n["x"], n["y"] = round(pos[n["id"]][0], 3), round(pos[n["id"]][1], 3)
    return nodes


# A node plus its two label lines needs roughly this much room, as a share of the drawing area.
BOX_W, BOX_H = 0.30, 0.19


def _normalise(pos):
    xs, ys = [p[0] for p in pos.values()], [p[1] for p in pos.values()]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    for p in pos.values():
        p[0] = 0.08 + 0.84 * (p[0] - x0) / ((x1 - x0) or 1)
        p[1] = 0.08 + 0.84 * (p[1] - y0) / ((y1 - y0) or 1)


def _box(n):
    k = min(1.0, math.sqrt(9.0 / max(n, 1)))
    return BOX_W * k, BOX_H * k


def _crowding(pos):
    """How many pairs of nodes sit closer than their label boxes allow (0 = nothing overlaps)."""
    ids = sorted(pos)
    bw, bh = _box(len(ids))
    return sum(1 for a in range(len(ids)) for b in range(a + 1, len(ids))
               if abs(pos[ids[a]][0] - pos[ids[b]][0]) < bw * 0.92 and abs(pos[ids[a]][1] - pos[ids[b]][1]) < bh * 0.92)


def _separate(pos, rounds=140):
    """Push apart any two nodes whose label boxes would overlap, then stretch back to fill the area. Deterministic."""
    ids = sorted(pos)
    bw, bh = _box(len(ids))
    for _ in range(rounds):
        moved = False
        for a in range(len(ids)):
            for b in range(a + 1, len(ids)):
                pa, pb = pos[ids[a]], pos[ids[b]]
                dx, dy = pb[0] - pa[0], pb[1] - pa[1]
                nx, ny = abs(dx) / bw, abs(dy) / bh
                if nx < 1 and ny < 1:
                    moved = True
                    # leave along the axis that is already further apart (in box units), so labels do not stack
                    if nx >= ny:
                        push = (1 - nx) * bw / 2 + 0.002
                        sx = 1 if dx >= 0 else -1
                        pa[0] -= sx * push
                        pb[0] += sx * push
                    else:
                        push = (1 - ny) * bh / 2 + 0.002
                        sy = 1 if dy >= 0 else -1
                        pa[1] -= sy * push
                        pb[1] += sy * push
        _normalise(pos)
        if not moved:
            break


def _node(nodes, nid, kind, label, sub="", flag=False):
    if nid not in nodes:
        nodes[nid] = {"id": nid, "kind": kind, "label": label, "sub": sub, "flag": flag}
    elif flag:
        nodes[nid]["flag"] = True


def _findings(g):
    """Run the four detectors and turn each hit into a finding with its own small evidence graph."""
    out, trace = [], []
    ov = find_overlapping_claims(g); trace.append(ov.pop("_trace"))
    dup = find_registry_duplicates(g); trace.append(dup.pop("_trace"))
    dr = find_double_retirements(g); trace.append(dr.pop("_trace"))
    lp = find_trading_loops(g); trace.append(lp.pop("_trace"))

    for kind, rows in (("overlap", ov["overlaps"]), ("registry_duplicate", dup["duplicates"])):
        for r in rows:
            nodes, edges = {}, []
            for pid, reg in ((r["a"], r["reg_a"]), (r["b"], r["reg_b"])):
                _node(nodes, pid, "project", pid, reg, True)
                _node(nodes, reg, "registry", reg)
                edges.append({"a": pid, "b": reg, "rel": "REGISTERED_ON"})
                for parcel in r["shared"]:
                    _node(nodes, parcel, "parcel", parcel, "shared land", True)
                    edges.append({"a": pid, "b": parcel, "rel": "COVERS", "flag": True})
            title = ("Same land listed on two registries" if kind == "registry_duplicate" else "Two projects claim the same land")
            summ = (f"{r['a']} ({r['reg_a']}) and {r['b']} ({r['reg_b']}) both cover " + ", ".join(r["shared"]) +
                    (" and have no other land." if kind == "registry_duplicate" else "."))
            out.append({"id": _fid(kind, f"{r['a']}|{r['b']}"), "type": kind, "key": f"{r['a']}|{r['b']}", "title": title,
                        "summary": summ, "projects": [r["a"], r["b"]], "credits": [], "buyers": [],
                        "ev_nodes": list(nodes.values()), "ev_edges": edges})

    trades = {}
    ids = [r["credit"] for r in dr["double_retirements"]] + [c for r in lp["loops"] for c in r["credits"]]
    if ids:
        for cid, a, ak, b, day in _rows(g, Q_TRADES, {"ids": ids}):
            trades.setdefault(cid, []).append((a, b, day))
    pro = {}
    if ids:
        for cid, pid in _rows(g, "MATCH (c:Credit)-[:ISSUED_FOR]->(p:Project) WHERE c.id IN $ids RETURN c.id, p.id", {"ids": ids}):
            pro[cid] = pid

    for r in dr["double_retirements"]:
        nodes, edges = {}, []
        cid, pid = r["credit"], r["project"]
        _node(nodes, cid, "credit", cid, f"{r['tonnes']} t", True)
        _node(nodes, pid, "project", pid)
        edges.append({"a": cid, "b": pid, "rel": "ISSUED_FOR"})
        for cl in r["claims"]:
            _node(nodes, cl["buyer"], "buyer", cl["name"], f"claim {cl['claim']}", True)
            edges.append({"a": cid, "b": cl["buyer"], "rel": "RETIRED_BY", "label": f"day {cl['day']}", "flag": True})
        for a, b, day in trades.get(cid, []):
            _node(nodes, a, "buyer", a); _node(nodes, b, "buyer", b)
            edges.append({"a": a, "b": b, "rel": "SOLD_TO", "label": f"day {day}"})
        who = " and ".join(cl["name"] for cl in r["claims"])
        out.append({"id": _fid("double_retirement", cid), "type": "double_retirement", "key": cid,
                    "title": "One credit retired twice", "summary": f"{cid} ({r['tonnes']} t, {pid}) was retired by {who}.",
                    "projects": [pid], "credits": [cid], "buyers": [cl["buyer"] for cl in r["claims"]],
                    "ev_nodes": list(nodes.values()), "ev_edges": edges})

    for r in lp["loops"]:
        nodes, edges = {}, []
        h = r["holders"]
        for b in h:
            _node(nodes, b, "buyer", b, "in the circle", True)
        for i, b in enumerate(h):
            edges.append({"a": b, "b": h[(i + 1) % len(h)], "rel": "SOLD_TO", "label": f"{len(r['credits'])} credit(s)", "flag": True})
        projs = sorted({pro[c] for c in r["credits"] if c in pro})
        for c in r["credits"]:
            if c in pro:
                _node(nodes, pro[c], "project", pro[c])
        for pid in projs:   # how the credits entered the circle: the developer's first sale
            entry = next((b for c in r["credits"] if pro.get(c) == pid for a, b, d in trades.get(c, []) if a.startswith("DEV-")), None)
            if entry:
                edges.append({"a": pid, "b": entry, "rel": "SOLD_VIA", "label": "first sale", "flag": True})
        out.append({"id": _fid("loop", r["key"]), "type": "loop", "key": r["key"], "title": "Credits sold in a circle",
                    "summary": f"{len(r['credits'])} credit(s) from {', '.join(projs)} were sold around {len(h)} holders ({', '.join(h)}) and came back to where they started.",
                    "projects": projs, "credits": r["credits"], "buyers": h,
                    "ev_nodes": list(nodes.values()), "ev_edges": edges})
    for f in out:
        f["weight"] = WEIGHTS[f["type"]]
    return out, trace


def _write_findings(g, findings):
    g.query("MATCH (f:Finding) DETACH DELETE f")
    if not findings:
        return
    g.query("UNWIND $r AS x CREATE (:Finding {id: x.id, type: x.type, key: x.key, weight: x.weight})",
            {"r": [{k: f[k] for k in ("id", "type", "key", "weight")} for f in findings]})
    pe = [{"f": f["id"], "t": p} for f in findings for p in f["projects"]]
    ce = [{"f": f["id"], "t": c} for f in findings for c in f["credits"]]
    if pe:
        g.query("UNWIND $r AS x MATCH (f:Finding {id: x.f}), (t:Project {id: x.t}) CREATE (f)-[:INVOLVES]->(t)", {"r": pe})
    if ce:
        g.query("UNWIND $r AS x MATCH (f:Finding {id: x.f}), (t:Credit {id: x.t}) CREATE (f)-[:INVOLVES]->(t)", {"r": ce})


def _case_id(finding_ids):
    return "CASE-" + hashlib.md5("|".join(sorted(finding_ids)).encode()).hexdigest()[:5].upper()


def _band(score):
    return "freeze" if score >= FREEZE_AT else "review" if score >= REVIEW_AT else "watch"


def scan(g):
    """Run every detector, store the findings in the graph, cluster them and score each cluster as a case."""
    findings, trace = _findings(g)
    _write_findings(g, findings)
    cl = cluster_suspicious(g); trace.append(cl.pop("_trace"))
    unaud = {r[0] for r in _rows(g, Q_UNAUDITED)}
    trace.append(_trace("scan", Q_UNAUDITED, detail=f"{len(unaud)} active project(s) with no audit report"))
    by_id = {f["id"]: f for f in findings}
    cases = []
    for c in cl["clusters"]:
        fs = [by_id[i] for i in c["findings"]]
        projects = sorted({p for f in fs for p in f["projects"]})
        signals = [{"signal": f["type"], "weight": f["weight"], "why": WHY[f["type"]], "finding": f["id"]} for f in fs]
        missing = sorted(set(projects) & unaud)
        if missing:
            signals.append({"signal": "no_audit", "weight": WEIGHTS["no_audit"], "why": WHY["no_audit"] + " (" + ", ".join(missing) + ")", "finding": None})
        signals.sort(key=lambda s: -s["weight"])
        score = _noisy_or([s["weight"] for s in signals])
        credits = sorted({x for f in fs for x in f["credits"]})
        # at risk: the credits named in the findings, or, for land claims, the project's credits not yet retired
        risky = _rows(g, Q_CREDITS, {"ids": credits}) if credits else _rows(g, Q_AT_RISK, {"pids": projects})
        freezable = [(i, t) for i, t, fz in risky]
        frozen_n = sum(1 for _, _, fz in risky if fz)
        nodes, edges = {}, []
        for f in fs:
            for n in f["ev_nodes"]:
                _node(nodes, n["id"], n["kind"], n["label"], n["sub"], n["flag"])
            edges.extend(f["ev_edges"])
        seen, uniq = {}, []
        for e in edges:
            k = (e["a"], e["b"], e["rel"])
            if k not in seen:
                seen[k] = e; uniq.append(e)
            elif e.get("flag"):
                seen[k]["flag"] = True          # the same link can appear in two findings
        for e in uniq:
            e.setdefault("flag", False)
        types = [f["type"] for f in fs]
        title = fs[0]["title"] if len(fs) == 1 else f"Linked scheme around {', '.join(projects[:2])}"
        cases.append({
            "id": _case_id(c["findings"]), "title": title, "score": score, "band": _band(score),
            "types": types, "findings": [{k: f[k] for k in ("id", "type", "title", "summary", "weight")} for f in fs],
            "projects": projects, "credits_at_risk": len(freezable), "tonnes_at_risk": int(sum(t for _, t in freezable)),
            "at_risk_ids": [i for i, _ in freezable][:400], "credits_frozen": frozen_n, "signals": signals,
            "evidence": {"nodes": _layout(list(nodes.values()), uniq), "edges": uniq},
            "suggested": ("freeze" if score >= FREEZE_AT else "refer" if score >= REVIEW_AT else "watch"),
            "summary": " ".join(f["summary"] for f in fs[:3]),
        })
    cases.sort(key=lambda c: (-c["score"], c["id"]))
    return {"cases": cases, "findings": len(findings), "trace": trace}


# ---- decisions (a person) and proposals (the agent) -----------------------------------------------------
def proposals(g):
    """Pending agent proposals by case id (the newest per case). Notes for a person: nothing here touches a credit."""
    rows = _rows(g, "MATCH (p:Proposal {status: 'pending'}) RETURN p.id, p.case, p.action, p.rationale, p.at ORDER BY p.at")
    return {r[1]: {"id": r[0], "action": r[2], "rationale": r[3], "by": "agent", "at": r[4]} for r in rows}


def propose(g, case, action, rationale):
    """The agent's only write: a recommendation attached to a case, for a person to accept or override.
    It changes no credit and closes no case. A newer proposal replaces the pending one for the same case."""
    if action not in ACTIONS:
        raise ValueError("action must be freeze, refer or dismiss")
    why = " ".join(str(rationale or "").split())[:400]
    if len(why) < 12:
        raise ValueError("give a one-sentence rationale that names the signals behind the action")
    now = _now()
    pid = "PROP-" + hashlib.md5(f"{case['id']}{action}{now}{why}".encode()).hexdigest()[:6].upper()
    g.query("MATCH (p:Proposal {case: $c, status: 'pending'}) SET p.status = 'replaced'", {"c": case["id"]})
    g.query(Q_PROPOSE, {"id": pid, "c": case["id"], "a": action, "r": why, "t": now, "s": case["score"]})
    g.query(Q_ABOUT, {"ps": list(case["projects"]), "id": pid})
    return {"proposal": {"id": pid, "case": case["id"], "action": action, "rationale": why, "at": now, "status": "pending"},
            "note": "Recorded as a proposal for the reviewer. Nothing was frozen, referred or dismissed: a person decides in the app.",
            "_trace": _trace("propose_action", Q_PROPOSE + "\n\n" + Q_ABOUT,
                             detail=f"proposed {action} on {case['id']}; waiting for a person to decide")}


def decisions(g):
    rows = _rows(g, "MATCH (k:Case) OPTIONAL MATCH (l:AuditLog)-[:RECORDS]->(k) "
                    "RETURN k.id, k.status, k.note, k.decided_at, count(l)")
    return {r[0]: {"status": r[1], "note": r[2], "decided_at": r[3], "log_entries": r[4]} for r in rows}


def decide(g, case, action, note=""):
    """Record a person's decision on a case. freeze: mark the case's at-risk credits frozen (they keep their status, and cannot be sold or retired). refer: ask the registries
    to resolve. dismiss: close as a false alarm. Everything is logged as an AuditLog node attached to the case."""
    if action not in ACTIONS:
        raise ValueError("action must be freeze, refer or dismiss")
    status = {"freeze": "frozen", "refer": "referred", "dismiss": "dismissed"}[action]
    now = _now()
    g.query("MERGE (k:Case {id: $id}) SET k.status = $s, k.note = $n, k.decided_at = $t",
            {"id": case["id"], "s": status, "n": (note or "")[:300], "t": now})
    pending = _rows(g, "MATCH (p:Proposal {case: $c, status: 'pending'}) RETURN p.action", {"c": case["id"]})
    proposed = pending[-1][0] if pending else ""
    if pending:                                  # the person's decision settles the agent's proposal either way
        g.query("MATCH (p:Proposal {case: $c, status: 'pending'}) SET p.status = $s, p.resolved_at = $t",
                {"c": case["id"], "s": "accepted" if proposed == action else "overridden", "t": now})
    frozen = 0
    if action == "freeze":
        ids = case["at_risk_ids"]
        rs = g.query("UNWIND $ids AS i MATCH (c:Credit {id: i}) WHERE c.frozen IS NULL SET c.frozen = true "
                     "WITH c MATCH (k:Case {id: $id}) CREATE (k)-[:FLAGS]->(c) RETURN count(c)", {"ids": ids, "id": case["id"]})
        frozen = rs.result_set[0][0] if rs.result_set else 0
    log_id = "LOG-" + hashlib.md5(f"{case['id']}{action}{now}".encode()).hexdigest()[:6].upper()
    g.query("MATCH (k:Case {id: $id}) CREATE (:AuditLog {id: $l, action: $a, by: 'human reviewer', at: $t, credits_frozen: $f, "
            "score: $sc, proposed: $pr})-[:RECORDS]->(k)",
            {"id": case["id"], "l": log_id, "a": action, "t": now, "f": frozen, "sc": case["score"], "pr": proposed})
    return {"case": case["id"], "status": status, "credits_frozen": frozen, "log": log_id, "at": now, "proposed": proposed}


Q_ACTIONS = ("MATCH (l:AuditLog)-[:RECORDS]->(k:Case) "
             "RETURN l.id, k.id, l.action, l.at, l.credits_frozen, l.by, k.note, l.proposed ORDER BY l.at DESC")


def list_actions(g):
    """Decisions a person has already made (with what the agent had proposed, if anything) and the proposals still waiting.
    Check before recommending or proposing something already done."""
    rows = _rows(g, Q_ACTIONS)
    waiting = proposals(g)
    return {"actions": [{"log": a, "case": b, "action": c, "at": d, "credits_frozen": e, "by": f, "note": n, "proposed": pr or ""}
                        for a, b, c, d, e, f, n, pr in rows],
            "pending_proposals": [{"case": cid, "action": p["action"], "rationale": p["rationale"], "at": p["at"]} for cid, p in waiting.items()],
            "_trace": _trace("list_actions", Q_ACTIONS, detail=f"{len(rows)} decision(s) logged, {len(waiting)} proposal(s) waiting")}


def run_cypher(g, query, limit=40):
    """Read-only escape hatch. FalkorDB's read-only query path rejects writes."""
    try:
        rs = g.ro_query(query)
    except Exception as e:
        return {"error": str(e)[:300]}
    rows = [[str(c) if not isinstance(c, (int, float, str, bool, type(None))) else c for c in r] for r in rs.result_set[:limit]]
    return {"columns": [h[1] if isinstance(h, (list, tuple)) else h for h in rs.header], "rows": rows,
            "truncated": len(rs.result_set) > limit, "_trace": _trace("run_cypher", query, detail=f"{len(rows)} row(s)")}


def overview(g):
    counts = dict(_rows(g, Q_OVERVIEW))
    edges = _rows(g, "MATCH ()-[r]->() RETURN count(r)")[0][0]
    return {"nodes": sum(counts.values()), "edges": edges, "by_label": counts}
