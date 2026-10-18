import os
import random

GRAPH_NAME = "ecograph"

REGISTRIES = [("REG-1", "VeriCarbon Registry"), ("REG-2", "TerraRegistry"), ("REG-3", "GreenLedger")]
COUNTRIES = ["Brazil", "Kenya", "Indonesia", "Peru", "India", "Ghana"]
KINDS = ["forest protection", "reforestation", "mangrove restoration", "cookstove", "peatland"]
AUDITORS = ["Northfield Assurance", "Cedar & Vale Verification", "Orbit Audit Partners"]
CORPORATES = ["Meridian Foods", "Altair Freight", "Quill Retail", "Borealis Steel", "Harbor Airlines", "Lumen Telecom"]


def _db():
    host = os.environ.get("FALKORDB_HOST")
    if host:
        from falkordb import FalkorDB
        return FalkorDB(host=host, port=int(os.environ.get("FALKORDB_PORT", "6379")),
                        password=os.environ.get("FALKORDB_PASSWORD") or None)
    from redislite.falkordb_client import FalkorDB
    return FalkorDB()


def generate(seed=7):
    rnd = random.Random(seed)
    parcels, projects, credits, buyers = [], [], [], []
    covers, trades, retires, audits = [], [], [], []


    n_proj = 41
    for i in range(1, n_proj + 1):
        buyers.append({"id": f"DEV-{i:02d}", "name": f"Developer {i:02d}", "kind": "developer"})
    for i in range(1, 21):
        buyers.append({"id": f"BR-{i:02d}", "name": f"Broker {i:02d}", "kind": "broker"})
    for i in range(1, 61):
        name = CORPORATES[i - 1] if i <= len(CORPORATES) else f"Corporate {i:02d}"
        buyers.append({"id": f"CO-{i:02d}", "name": name, "kind": "corporate"})
    devs = [b["id"] for b in buyers if b["kind"] == "developer"]
    brokers = [b["id"] for b in buyers if b["kind"] == "broker"]
    corps = [b["id"] for b in buyers if b["kind"] == "corporate"]
    ids_for_loops = {"ring": ("BR-02", "CO-08", "BR-05"), "iso": ("BR-09", "BR-11", "CO-22", "BR-12"),
                     "swap": ("BR-03", "BR-04")}
    reserved = {b for g in ids_for_loops.values() for b in g}
    free_brokers = [b for b in brokers if b not in reserved]
    free_corps = [c for c in corps if c not in reserved and c != "CO-01"]


    plan = {}
    pc = 0

    def new_parcel(geohash=None, country=None):
        nonlocal pc
        pc += 1
        pid = f"LP-{pc:03d}"
        parcels.append({"id": pid, "geohash": geohash or f"{rnd.choice('kmsuv')}{rnd.choice('0123456789bcdefgh')}"
                                                         f"{rnd.choice('0123456789bcdefgh')}{rnd.choice('0123456789bcdefgh')}"
                                                         f"{rnd.choice('0123456789bcdefgh')}{rnd.choice('0123456789bcdefgh')}",
                        "hectares": rnd.randrange(80, 900, 10), "country": country or rnd.choice(COUNTRIES)})
        return pid

    shared_31 = None
    for i in range(1, n_proj + 1):
        if i == 41:
            plan[i] = list(plan[12]); continue
        if i == 19:
            plan[i] = [shared_31, new_parcel()]; continue
        if i == 26:
            plan[i] = [plan[25][0], new_parcel()]; continue
        plan[i] = [new_parcel() for _ in range(rnd.choice([1, 2]))]
        if i == 7:
            shared_31 = plan[7][0]

    near_a = new_parcel(geohash="kd7m2a", country="Kenya")
    near_b = new_parcel(geohash="kd7m2b", country="Kenya")
    plan[35], plan[36] = [near_a], [near_b]

    old_land = new_parcel(country="Peru")
    plan[33], plan[34] = [old_land], [old_land]

    reg_of = {i: REGISTRIES[i % 3][0] for i in range(1, n_proj + 1)}
    reg_of[7], reg_of[19] = "REG-1", "REG-2"
    reg_of[12], reg_of[41] = "REG-1", "REG-2"
    reg_of[25] = reg_of[26] = "REG-3"
    unaudited = {19, 12, 41, 5, 14, 29, 38}

    for i in range(1, n_proj + 1):
        pid = f"P-{i:02d}"
        ended = i == 33
        projects.append({"id": pid, "name": f"{rnd.choice(KINDS).title()} {pid}", "type": KINDS[i % len(KINDS)],
                         "country": next(p["country"] for p in parcels if p["id"] == plan[i][0]),
                         "vintage": 2014 if ended else rnd.choice([2019, 2020, 2021, 2022]),
                         "status": "ENDED" if ended else "ACTIVE", "registry": reg_of[i], "developer": f"DEV-{i:02d}"})
        for lp in plan[i]:
            covers.append({"p": pid, "lp": lp})
        if i not in unaudited:
            audits.append({"p": pid, "id": f"AR-{i:02d}", "auditor": AUDITORS[i % 3], "date": f"202{rnd.choice([2, 3, 4])}-0{rnd.randint(1, 9)}-1{rnd.randint(0, 9)}",
                           "canopy_before": rnd.randint(55, 70), "canopy_after": rnd.randint(71, 90)})


    by_proj = {}
    n = 0
    for pr in projects:
        by_proj[pr["id"]] = []
        for _ in range(rnd.randint(28, 52) if pr["status"] == "ACTIVE" else 20):
            n += 1
            cid = f"CR-{n:05d}"
            credits.append({"id": cid, "project": pr["id"], "vintage": pr["vintage"], "tonnes": rnd.randrange(50, 500, 10),
                            "status": "ACTIVE"})
            by_proj[pr["id"]].append(cid)
    cr = {c["id"]: c for c in credits}

    def take(pid, k):
        got, by_proj[pid] = by_proj[pid][:k], by_proj[pid][k:]
        return got

    def trade(cid, a, b, day, price=None):
        trades.append({"credit": cid, "a": a, "b": b, "day": day, "price": price or rnd.randrange(8, 24)})

    def retire(cid, b, day, claim):
        retires.append({"credit": cid, "b": b, "day": day, "claim": claim})
        cr[cid]["status"] = "RETIRED"

    truth = {"findings": [], "decoys": []}


    truth["findings"].append({"type": "overlap", "key": "P-07|P-19"})
    loop_credits = take("P-19", 3)
    a, b, c = ids_for_loops["ring"]
    for k, cid in enumerate(loop_credits):
        d = 20 + 12 * k
        trade(cid, "DEV-19", a, d); trade(cid, a, b, d + 3); trade(cid, b, c, d + 6); trade(cid, c, a, d + 9)
    truth["findings"].append({"type": "loop", "key": "|".join(sorted(ids_for_loops["ring"]))})
    [dr1] = take("P-19", 1)
    trade(dr1, "DEV-19", "BR-07", 30); trade(dr1, "BR-07", "CO-14", 34)
    retire(dr1, "CO-14", 40, "CLM-4410"); retire(dr1, "CO-31", 58, "CLM-5207")
    truth["findings"].append({"type": "double_retirement", "key": dr1})


    [dr2] = take("P-03", 1)
    trade(dr2, "DEV-03", "BR-13", 66); trade(dr2, "BR-13", "CO-17", 70)
    retire(dr2, "CO-17", 75, "CLM-6120"); retire(dr2, "CO-40", 90, "CLM-6388")
    truth["findings"].append({"type": "double_retirement", "key": dr2})

    iso = ids_for_loops["iso"]
    for k, cid in enumerate(take("P-27", 2)):
        d = 100 + 15 * k
        trade(cid, "DEV-27", iso[0], d)
        for j in range(len(iso)):
            trade(cid, iso[j], iso[(j + 1) % len(iso)], d + 3 * (j + 1))
    truth["findings"].append({"type": "loop", "key": "|".join(sorted(iso))})


    truth["findings"].append({"type": "registry_duplicate", "key": "P-12|P-41"})

    truth["findings"].append({"type": "overlap", "key": "P-25|P-26"})


    truth["decoys"] = [
        {"note": "neighbouring parcels with near-identical geohashes (P-35, P-36), not the same land"},
        {"note": "ended project followed by a new one on the same parcel (P-33, P-34), a legitimate succession"},
        {"note": "long resale chain of five hops with no repeated holder"},
        {"note": "BR-03 and BR-04 swap different credits both ways, a 2-cycle that never returns the same credit"},
        {"note": "Meridian Foods (CO-01) retires 160 credits, a large honest buyer"},
        {"note": "seven projects have no audit report on file, a weak signal that never raises a case alone"},
    ]
    for cid in take("P-14", 5):
        chain = ["DEV-14", "BR-14", "BR-15", "BR-16", "BR-17", "CO-33"]
        for j in range(5):
            trade(cid, chain[j], chain[j + 1], 30 + 5 * j)
        retire(cid, "CO-33", 60, f"CLM-{rnd.randint(7000, 7999)}")
    s1, s2 = ids_for_loops["swap"]
    for k, cid in enumerate(take("P-16", 10)):
        trade(cid, "DEV-16", s1 if k % 2 == 0 else s2, 40 + k)
        trade(cid, s1 if k % 2 == 0 else s2, s2 if k % 2 == 0 else s1, 55 + k)
    big = 0
    for pid, k in (("P-20", len(by_proj["P-20"])), ("P-02", 20), ("P-04", 20), ("P-06", 20), ("P-08", 20), ("P-09", 20)):
        for cid in take(pid, k):
            trade(cid, f"DEV-{pid[2:]}", "CO-01", 82); retire(cid, "CO-01", 88, f"CLM-{rnd.randint(8000, 8999)}"); big += 1
    truth["decoys"][4]["note"] = f"Meridian Foods (CO-01) retires {big} credits, a large honest buyer"


    for pid, cids in by_proj.items():
        dev = f"DEV-{pid[2:]}"
        for cid in cids:
            r = rnd.random()
            if r < 0.45 or projects[int(pid[2:]) - 1]["status"] == "ENDED":
                continue
            hops = rnd.choice([1, 1, 2, 2, 3])
            holders = [dev] + [rnd.choice(free_brokers) for _ in range(hops - 1)] + [rnd.choice(free_corps)]
            if len(set(holders)) < len(holders):
                holders = [dev] + rnd.sample(free_brokers, hops - 1) + [rnd.choice(free_corps)]
            day = rnd.randint(5, 200)
            for j in range(len(holders) - 1):
                trade(cid, holders[j], holders[j + 1], day + 3 * j)
            if rnd.random() < 0.7:
                retire(cid, holders[-1], day + 3 * hops + 5, f"CLM-{rnd.randint(1000, 9999)}")

    data = {"registries": [{"id": i, "name": n} for i, n in REGISTRIES], "parcels": parcels, "projects": projects,
            "credits": credits, "buyers": buyers, "covers": covers, "trades": trades, "retires": retires,
            "audits": audits}
    return data, truth


def _batches(rows, size=500):
    for i in range(0, len(rows), size):
        yield rows[i:i + size]


def load(g, seed=7):
    data, truth = generate(seed)
    g.query("MATCH (n) DETACH DELETE n")
    for lab in ("Credit", "Buyer", "Project", "LandParcel", "Registry", "Finding", "Case"):
        try:
            g.query(f"CREATE INDEX FOR (n:{lab}) ON (n.id)")
        except Exception:
            pass
    g.query("UNWIND $r AS x CREATE (:Registry {id:x.id, name:x.name})", {"r": data["registries"]})
    g.query("UNWIND $r AS x CREATE (:LandParcel {id:x.id, geohash:x.geohash, hectares:x.hectares, country:x.country})",
            {"r": data["parcels"]})
    g.query("UNWIND $r AS x CREATE (:Buyer {id:x.id, name:x.name, kind:x.kind})", {"r": data["buyers"]})
    g.query("UNWIND $r AS x CREATE (:Project {id:x.id, name:x.name, type:x.type, country:x.country, vintage:x.vintage, status:x.status})",
            {"r": data["projects"]})
    g.query("UNWIND $r AS x MATCH (p:Project {id:x.id}), (g:Registry {id:x.registry}), (d:Buyer {id:x.developer}) "
            "CREATE (p)-[:REGISTERED_ON]->(g), (p)-[:DEVELOPED_BY]->(d)", {"r": data["projects"]})
    g.query("UNWIND $r AS x MATCH (p:Project {id:x.p}), (l:LandParcel {id:x.lp}) CREATE (p)-[:COVERS]->(l)", {"r": data["covers"]})
    g.query("UNWIND $r AS x MATCH (p:Project {id:x.p}) CREATE (p)-[:VERIFIED_BY]->(:AuditReport {id:x.id, auditor:x.auditor, "
            "date:x.date, canopy_before:x.canopy_before, canopy_after:x.canopy_after})", {"r": data["audits"]})
    for chunk in _batches(data["credits"]):
        g.query("UNWIND $r AS x MATCH (p:Project {id:x.project}) CREATE (:Credit {id:x.id, vintage:x.vintage, tonnes:x.tonnes, "
                "status:x.status})-[:ISSUED_FOR]->(p)", {"r": chunk})
    for chunk in _batches(data["trades"]):
        g.query("UNWIND $r AS x MATCH (a:Buyer {id:x.a}), (b:Buyer {id:x.b}) "
                "CREATE (a)-[:SOLD_TO {credit:x.credit, day:x.day, price:x.price}]->(b)", {"r": chunk})
    g.query("UNWIND $r AS x MATCH (c:Credit {id:x.credit}), (b:Buyer {id:x.b}) "
            "CREATE (c)-[:RETIRED_BY {day:x.day, claim:x.claim}]->(b)", {"r": data["retires"]})
    g.query("UNWIND $r AS x MATCH (c:Credit {id:x.id}) SET c.status = x.status",
            {"r": [{"id": c["id"], "status": c["status"]} for c in data["credits"] if c["status"] != "ACTIVE"]})
    return truth


def open_graph(fresh=True, seed=7):
    g = _db().select_graph(GRAPH_NAME)
    if fresh:
        load(g, seed)
    return g
