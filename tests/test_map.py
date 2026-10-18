from eco import detect as D, graph


def test_land_map_places_every_parcel_and_flags_cases():
    g = graph.open_graph(fresh=True)
    scan = D.scan(g)
    cases = [{**c, "status": "open"} for c in scan["cases"]]
    m = D.land_map(g, cases)
    assert len(m["parcels"]) == 60
    assert all(-90 <= p["lat"] <= 90 and -180 <= p["lon"] <= 180 for p in m["parcels"])
    assert any(p["state"] == "overlap" for p in m["parcels"])
    assert sum(c["tonnes_at_risk"] for c in m["countries"]) == sum(c["tonnes_at_risk"] for c in cases)


def test_decided_cases_leave_the_map_clean():
    g = graph.open_graph(fresh=True)
    cases = [{**c, "status": "frozen"} for c in D.scan(g)["cases"]]
    m = D.land_map(g, cases)
    assert all(p["state"] == "ok" for p in m["parcels"])
