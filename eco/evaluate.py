import json
import sys

from eco import detect as D, graph


def detected(g):
    keys = set()
    for r in D.find_overlapping_claims(g)["overlaps"]:
        keys.add(("overlap", f"{r['a']}|{r['b']}"))
    for r in D.find_registry_duplicates(g)["duplicates"]:
        keys.add(("registry_duplicate", f"{r['a']}|{r['b']}"))
    for r in D.find_double_retirements(g)["double_retirements"]:
        keys.add(("double_retirement", r["credit"]))
    for r in D.find_trading_loops(g)["loops"]:
        keys.add(("loop", r["key"]))
    return keys


def evaluate(g=None):
    g = g or graph.open_graph(fresh=False)
    truth = graph.load(g)
    planted = {(f["type"], f["key"]) for f in truth["findings"]}
    found = detected(g)
    tp, fp, fn = planted & found, found - planted, planted - found
    by_type = {}
    for t in sorted({k[0] for k in planted | found}):
        p, f = {k for k in planted if k[0] == t}, {k for k in found if k[0] == t}
        by_type[t] = {"planted": len(p), "found": len(f), "correct": len(p & f), "false_alarms": len(f - p)}
    return {"planted": len(planted), "found": len(found), "true_positives": len(tp),
            "false_positives": sorted(fp), "missed": sorted(fn), "decoys_planted": len(truth["decoys"]),
            "precision": round(len(tp) / len(found), 3) if found else None,
            "recall": round(len(tp) / len(planted), 3) if planted else None, "by_type": by_type,
            "decoys": [d["note"] for d in truth["decoys"]]}


if __name__ == "__main__":
    r = evaluate()
    print(json.dumps(r, indent=2, default=list))
    sys.exit(0 if not r["false_positives"] and not r["missed"] else 1)
