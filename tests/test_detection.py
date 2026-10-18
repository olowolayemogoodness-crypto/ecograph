import pytest

from eco import detect as D, graph, evaluate


@pytest.fixture(scope="module")
def g():
    g = graph.open_graph(fresh=True)
    return g


def test_every_planted_fraud_found_and_no_decoy_flagged(g):
    r = evaluate.evaluate(g)
    assert r["missed"] == [] and r["false_positives"] == []
    assert r["precision"] == 1.0 and r["recall"] == 1.0
    assert r["planted"] == 7          # 2 overlaps, 1 registry duplicate, 2 double retirements, 2 loops


def test_loops_need_the_same_credit_and_three_holders(g):
    graph.load(g)
    loops = D.find_trading_loops(g)["loops"]
    keys = {l["key"] for l in loops}
    assert keys == {"BR-02|BR-05|CO-08", "BR-09|BR-11|BR-12|CO-22"}
    assert not any({"BR-03", "BR-04"} & set(l["holders"]) for l in loops)      # swap decoy
    assert not any("BR-14" in l["holders"] for l in loops)                    # long honest chain decoy
    assert sum(len(l["credits"]) for l in loops) == 5


def test_land_decoys_not_flagged(g):
    pairs = {(r["a"], r["b"]) for r in D.find_overlapping_claims(g)["overlaps"]} | \
            {(r["a"], r["b"]) for r in D.find_registry_duplicates(g)["duplicates"]}
    assert ("P-07", "P-19") in pairs and ("P-12", "P-41") in pairs and ("P-25", "P-26") in pairs
    assert not any({"P-33", "P-34"} == {a, b} or {"P-35", "P-36"} == {a, b} for a, b in pairs)


def test_duplicate_is_not_also_reported_as_overlap(g):
    assert {(r["a"], r["b"]) for r in D.find_overlapping_claims(g)["overlaps"]} == {("P-07", "P-19"), ("P-25", "P-26")}
    assert {(r["a"], r["b"]) for r in D.find_registry_duplicates(g)["duplicates"]} == {("P-12", "P-41")}


def test_big_honest_buyer_is_not_a_double_retirement(g):
    retired = g.ro_query("MATCH (c:Credit)-[:RETIRED_BY]->(:Buyer {id:'CO-01'}) RETURN count(c)").result_set[0][0]
    assert retired > 100
    assert len(D.find_double_retirements(g)["double_retirements"]) == 2        # only the two planted credits


def test_scan_groups_findings_into_five_cases_and_ring_is_one_cluster(g):
    graph.load(g)
    scan = D.scan(g)
    assert scan["findings"] == 7 and len(scan["cases"]) == 5
    ring = scan["cases"][0]
    assert sorted(ring["types"]) == ["double_retirement", "loop", "overlap"] and ring["projects"] == ["P-07", "P-19"]
    assert ring["score"] >= D.FREEZE_AT and ring["suggested"] == "freeze"
    lone_loop = next(c for c in scan["cases"] if c["types"] == ["loop"])
    assert lone_loop["suggested"] == "refer" and lone_loop["score"] < D.FREEZE_AT


def test_score_is_explainable_noisy_or(g):
    for c in D.scan(g)["cases"]:
        expected = 1.0
        for s in c["signals"]:
            expected *= 1 - s["weight"]
        assert c["score"] == pytest.approx(round(1 - expected, 3))
        assert all(s["why"] for s in c["signals"])


def test_missing_audit_alone_never_raises_a_case(g):
    scan = D.scan(g)
    flagged_projects = {p for c in scan["cases"] for p in c["projects"]}
    unaudited_clean = {"P-05", "P-14", "P-29", "P-38"}
    assert not (unaudited_clean & flagged_projects)


def test_upstream_trace_follows_a_credit_to_the_land(g):
    t = D.trace_credit_upstream(g, "CR-00694")
    assert t["project"]["id"] == "P-19" and len(t["retired"]) == 2 and t["rival_claims"][0]["project"] == "P-07"
    assert t["hops"] >= 4 and any("more than once" in f for f in t["flags"])
    assert "error" in D.trace_credit_upstream(g, "CR-NOPE")


def test_betweenness_is_context_not_proof(g):
    r = D.rank_intermediaries(g, 5)
    assert len(r["ranking"]) == 5 and "proves nothing" in r["note"]


def test_run_cypher_is_read_only(g):
    assert "error" in D.run_cypher(g, "CREATE (:Evil)")
    assert D.run_cypher(g, "MATCH (r:Registry) RETURN count(r)")["rows"] == [[3]]


def test_freeze_is_a_logged_human_decision(g):
    graph.load(g)
    scan = D.scan(g)
    case = scan["cases"][0]
    res = D.decide(g, case, "freeze", "checked with registry")
    assert res["credits_frozen"] == case["credits_at_risk"] == 4
    assert g.ro_query("MATCH (c:Credit) WHERE c.frozen = true RETURN count(c)").result_set[0][0] == 4
    acts = D.list_actions(g)["actions"]
    assert acts[0]["case"] == case["id"] and acts[0]["action"] == "freeze" and acts[0]["by"] == "human reviewer"
    again = D.scan(g)                      # the decision survives a re-scan
    assert D.decisions(g)[case["id"]]["status"] == "frozen"
    with pytest.raises(ValueError):
        D.decide(g, case, "delete")
