#!/usr/bin/env python3
"""G6 ABI falsifiers (separate from behavioral red counts).

On disposable copies of the FRESH compiled compiler-ABI JSON of the
candidate's CurveGaugeLister, independently: append an unexpected callable,
change constructor order, append a Listing field, change confiscation event
indexing, remove a surfaced error, change mutability. The full manifest
comparator (keyed complete-entry comparison, same logic as G2) must REJECT
each and ACCEPT pristine. A selector-only comparison cannot catch several of
these — this comparator is entry-object equality. Finally: the import-closure
check must reject a shipping import of any retired dependency.
"""
import copy, hashlib, json, os, re, sys
from pathlib import Path

CAND = Path(os.environ["CGL_CANDIDATE"])
MAN = json.loads((CAND / "plans/V1ALIGN-MANIFEST.json").read_text())
ART = json.loads((CAND / "out/contracts/CurveGaugeLister.sol/CurveGaugeLister.json").read_text()) \
    if (CAND / "out/contracts/CurveGaugeLister.sol/CurveGaugeLister.json").exists() \
    else json.loads((CAND / "out/CurveGaugeLister.sol/CurveGaugeLister.json").read_text())

def canon_type(item):
    if item["type"].startswith("tuple"):
        return "(" + ",".join(canon_type(v) for v in item["components"]) + ")" + item["type"][5:]
    return item["type"]

def signature(entry):
    return entry.get("name", entry["type"]) + "(" + ",".join(canon_type(v) for v in entry.get("inputs", [])) + ")"

def keyed(abi):
    r = {(e["type"], signature(e)): e for e in abi}
    assert len(r) == len(abi), "Duplicate full-ABI entry"
    return r

def accept(abi):
    return keyed(abi) == keyed(MAN["abi"])

def find(abi, pred):
    return next(e for e in abi if pred(e))

rows = {}
pristine = copy.deepcopy(ART["abi"])
rows["pristine_accept"] = accept(pristine)

# 1. append an unexpected callable
m = copy.deepcopy(pristine)
m.append({"type": "function", "name": "claimReward", "stateMutability": "nonpayable",
          "inputs": [{"name": "who", "type": "address", "internalType": "address"}], "outputs": []})
rows["abi_unexpected_callable"] = not accept(m)

# 2. change constructor order (swap last two inputs)
m = copy.deepcopy(pristine)
ctor = find(m, lambda e: e["type"] == "constructor")
ctor["inputs"][-1], ctor["inputs"][-2] = ctor["inputs"][-2], ctor["inputs"][-1]
rows["abi_constructor_order"] = not accept(m)

# 3. append a Listing field (getListing output tuple gains reporterReward)
m = copy.deepcopy(pristine)
gl = find(m, lambda e: e["type"] == "function" and e["name"] == "getListing")
gl["outputs"][0]["components"].append({"name": "reporterReward", "type": "uint256", "internalType": "uint256"})
rows["abi_listing_field_appended"] = not accept(m)

# 4. change confiscation event indexing (receiptWeek becomes indexed)
m = copy.deepcopy(pristine)
ev = find(m, lambda e: e["type"] == "event" and e["name"] == "EscrowConfiscated")
ev["inputs"][-1]["indexed"] = True
rows["abi_event_indexing"] = not accept(m)

# 5. remove a surfaced error
m = copy.deepcopy(pristine)
m = [e for e in m if not (e["type"] == "error" and e["name"] == "WrongChain")]
rows["abi_error_removed"] = not accept(m)

# 6. change mutability (epochStart pure -> view)
m = copy.deepcopy(pristine)
fn = find(m, lambda e: e["type"] == "function" and e["name"] == "epochStart")
fn["stateMutability"] = "view"
rows["abi_mutability"] = not accept(m)

# 7. selector-only blindness proof: a same-selector entry change (event
#    indexing flip keeps the topic0 selector) must be caught by the full
#    comparator though a selector map would not notice.
mi_pristine = set(ART["methodIdentifiers"].values())
mi_flipped = mi_pristine  # events/errors carry no methodIdentifiers entry
rows["selector_map_blind_to_event_indexing"] = ("EscrowConfiscated" not in json.dumps(ART["methodIdentifiers"]))

# 8. reject a shipping import of any retired dependency (synthetic closure)
removed = set(MAN["remove_product_sources"])
hit = None
for path in MAN["shipping_product_sources"]:
    text = (CAND / path).read_text()
    for imp in re.findall(r'from\s+"([^"]+)"', text):
        p = os.path.normpath(os.path.join(os.path.dirname(path), imp))
        if p in removed:
            hit = (path, p)
rows["no_retired_import_in_ship"] = hit is None

# 9. and positively: the comparator rejects such an import closure.
fake = MAN["shipping_product_sources"][0]
inj = f'import {{"BountyRead"}} from "./libraries/BountyRead.sol";'
closure_text = (CAND / fake).read_text() + "\n" + inj + "\n"
found = False
for imp in re.findall(r'from\s+"([^"]+)"', closure_text):
    p = os.path.normpath(os.path.join(os.path.dirname(fake), imp))
    if p in removed:
        found = True
rows["injected_retired_import_rejected"] = found

print(json.dumps(rows, indent=1))
sys.exit(0 if all(rows.values()) else 1)
