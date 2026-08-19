#!/usr/bin/env python3
"""One-off migration: name every clause after its language.

Run once, for the engines committed before clause namespacing existed
(2026-08-12, docs/superpowers/decisions/2026-08-12-cross-program-composition.md).
Composition unions the clause spaces of several languages, so a bare `report` in
one would collide with a bare `report` in another; the kernel now refuses a
clause a language did not name after itself.

Why a script and not a re-mint: a re-mint is the sanctioned path but rewrites
whole engines, and DESIGN records mints regressing behaviour a program never
mentioned. This transformation is mechanical, total and reviewable in the diff:
it renames `clause.<n>` to `clause.<lang>-<n>` in the rules, and rewrites every
definition and call site of those names inside clause and claim bodies. Nothing
else is touched, and every engine is re-verified afterwards by `lips check`,
which runs its committed claims and expects.

Usage: migrate-clause-namespace.py <engine.rules> [...]
"""
import re
import sys
from pathlib import Path


def clause_names(text):
    """Every clause this engine defines, from its rule emit paths."""
    # Scheme identifiers are wider than a word: keep? and matches? are clause
    # names here, and a charset that stops at ? renames neither, silently.
    return sorted(set(re.findall(r"clause\.([A-Za-z0-9_?!*+<>=-]+)", text)),
                  key=len, reverse=True)


def migrate(path):
    p = Path(path)
    # The language is the engine's own name: <lang>/<world>/<lang>.rules
    lang = p.name.rsplit(".", 1)[0]
    text = p.read_text()
    names = [n for n in clause_names(text) if not n.startswith(lang + "-")]
    if not names:
        return f"{p}: already namespaced"

    out = text
    for n in names:
        new = f"{lang}-{n}"
        # the emit path itself
        out = re.sub(r"clause\." + re.escape(n) + r'(?=[\s"])', f"clause.{new}", out)
        # every definition and call site inside a body: the name in head position
        # of an s-expression, which is where a clause name can appear at all,
        # since the clause language is first order and has no higher-order values.
        out = re.sub(r"\(" + re.escape(n) + r"(?=[\s)])", "(" + new, out)
        # a predicate's name ends in ? or !, which are not word boundaries
        out = re.sub(r"\((" + re.escape(n) + r")(?=[\s)])", "(" + new, out)
    p.write_text(out)
    return f"{p}: {len(names)} clause(s) -> {lang}-*"


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for arg in sys.argv[1:]:
        print(migrate(arg))
