#!/usr/bin/env python3
"""r3docs G0 helper: string-aware token comparison that strips comments and
whitespace but retains string literals and token boundaries.

Usage: token_cmp.py OLD_FILE NEW_FILE
Exit 0 + identical=... if the executable token streams match exactly.
Exit 1 with a diff of the first divergence otherwise.
"""
import subprocess
import sys


def strip_keep_tokens(text):
    """Return list of whitespace-separated tokens outside comments.

    '//' line comments and '/* */' block comments are removed only when
    outside a string literal; string literals are kept whole (including
    spaces), with escapes tracked. Solidity has no nested block comments.
    """
    tokens = []
    buf = []
    i = 0
    n = len(text)
    cur = None  # current token chars

    def flush():
        nonlocal cur
        if cur:
            tokens.append("".join(cur))
            cur = None

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and nxt == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            if cur is None:
                cur = []
            cur.append('"')
            i += 1
            while i < n:
                if text[i] == "\\":
                    cur.append(text[i:i + 2])
                    i += 2
                    continue
                if text[i] == '"':
                    cur.append('"')
                    i += 1
                    break
                cur.append(text[i])
                i += 1
            continue
        if c.isspace():
            flush()
            i += 1
            continue
        if cur is None:
            cur = []
        cur.append(c)
        i += 1
    flush()
    return tokens


def main():
    old, new = sys.argv[1], sys.argv[2]
    if old.startswith("git:"):
        out = subprocess.run(
            ["git", "show", old[4:]], cwd="/home/winny/curve-gauge-lister",
            capture_output=True, text=True, check=True)
        old_text = out.stdout
    else:
        old_text = open(old).read()
    new_text = open(new).read()
    a = strip_keep_tokens(old_text)
    b = strip_keep_tokens(new_text)
    if a == b:
        print(f"IDENTICAL tokens={len(a)} file={new}")
        return 0
    for k, (x, y) in enumerate(zip(a, b)):
        if x != y:
            print(f"DIVERGE at token {k} of {new}:\n  old: {x!r}\n  new: {y!r}")
            return 1
    print(f"LENGTH DIFF {new}: old {len(a)} vs new {len(b)}; extra: {(a[len(b):] or b[len(a):])[:5]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
