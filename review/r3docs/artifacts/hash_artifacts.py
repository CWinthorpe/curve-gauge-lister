#!/usr/bin/env python3
"""r3docs gate helper: hash all forge artifacts under an out dir.

For every artifact JSON, record:
  - file sha256 (whole JSON on disk)
  - full creation hex sha256, full runtime hex sha256
  - validated Solidity metadata trailer parse on EACH bytecode:
      last 2 bytes = big-endian CBOR length L; trailer = last L+2 bytes;
      trailer[0] must be 0xa2 (2-item map); map keys must be exactly
      {b'ipfs', b'solc'} decoded with a minimal CBOR walker.
    executable = bytes minus the trailer; hash the executable hex.
  - raw trailer hex retained
Comment-only source edits must move ONLY metadata trailers (full hashes can
change because the metadata embeds source keccak); executable hashes must not
move.
"""
import hashlib
import json
import pathlib
import sys


def cbor_walk(d, i):
    """Skip exactly one CBOR data item starting at i; return its end index."""
    ai = d[i]
    major = ai >> 5
    add = ai & 0x1F
    if add < 24:
        arg = add
        j = i + 1
    elif add == 24:
        arg = d[i + 1]
        j = i + 2
    elif add == 25:
        arg = int.from_bytes(d[i + 1:i + 3], "big")
        j = i + 3
    elif add == 26:
        arg = int.from_bytes(d[i + 1:i + 5], "big")
        j = i + 5
    elif add == 27:
        arg = int.from_bytes(d[i + 1:i + 9], "big")
        j = i + 9
    else:
        raise ValueError("indefinite-length CBOR not supported here")
    if major in (0, 1, 7):
        return j
    if major in (2, 3):  # bytes / text: argument is the payload length
        return j + arg
    if major == 4:  # array
        for _ in range(arg):
            j = cbor_walk(d, j)
        return j
    if major == 5:  # map
        for _ in range(arg):
            j = cbor_walk(d, j)
            j = cbor_walk(d, j)
        return j
    raise ValueError("unsupported CBOR major type")


def split_metadata(hexstr):
    """Return (executable_hex, trailer_hex, keys) or raise."""
    d = bytes.fromhex(hexstr)
    if len(d) < 3:
        raise ValueError("bytecode too short for a metadata trailer")
    L = int.from_bytes(d[-2:], "big")
    if L <= 0 or L > len(d) - 2:
        raise ValueError("metadata length field out of range")
    trailer = d[-(L + 2):-2]
    if not trailer or trailer[0] != 0xA2:
        raise ValueError("trailer is not a 2-item CBOR map")
    i = 1
    keys = []
    for _ in range(2):
        if trailer[i] != 0x64 or trailer[i + 1:i + 5] not in (b"ipfs", b"solc"):
            raise ValueError("unexpected metadata map key")
        keys.append(trailer[i + 1:i + 5])
        i += 5
        i = cbor_walk(trailer, i)
    if i != len(trailer):
        raise ValueError("trailer not fully consumed")
    if sorted(keys) != [b"ipfs", b"solc"]:
        raise ValueError("metadata keys not {ipfs, solc}")
    return hexstr[:len(hexstr) - 2 * (L + 2)], trailer.hex(), [k.decode() for k in keys]


def sha(s):
    return hashlib.sha256(s if isinstance(s, bytes) else s.encode()).hexdigest()


def main(outdir):
    out = pathlib.Path(outdir)
    records = {}
    for p in sorted(x for x in out.glob("*/*.json") if x.parent.name != "build-info"):
        art = json.loads(p.read_text())
        rec = {"file_sha256": sha(p.read_bytes())}
        for side, key in (("creation", "bytecode"), ("runtime", "deployedBytecode")):
            obj = (art.get(key) or {}).get("object", "")
            if obj.startswith("0x") or obj.startswith("0X"):
                obj = obj[2:]
            if not obj:
                continue
            r = {"full_sha256": sha(obj)}
            try:
                exec_hex, trailer, keys = split_metadata(obj)
                r["executable_sha256"] = sha(exec_hex)
                r["metadata_trailer"] = trailer
                r["metadata_keys"] = keys
            except Exception as e:  # noqa: BLE001 - record, do not hide
                r["metadata_parse_error"] = str(e)
            rec[side] = r
        for extra in ("abi", "methodIdentifiers", "storageLayout"):
            if extra in art:
                rec[extra + "_sha256"] = sha(json.dumps(art[extra], sort_keys=True))
        records[f"{p.parent.name}/{p.name}"] = rec
    print(json.dumps(records, indent=1, sort_keys=True))


if __name__ == "__main__":
    main(sys.argv[1])
