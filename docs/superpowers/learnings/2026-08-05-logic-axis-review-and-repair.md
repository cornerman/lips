# Reviewing the Logic Axis Against Itself

Recorded 2026-08-05, on branch `logscan-clauses`, after a full review of the
sixty commits that built the logic axis. The branch was asked one question: does
it do what it says. The answer was mostly yes and five times no, and every one
of the five was the same defect class the branch exists to eliminate — wrong
behaviour with every gate green.

## Why This Document Exists

The branch had already survived two review passes and a six-scenario validation
campaign. It still shipped three silent-wrong bugs. What found them was not
reading harder; it was **running the thing and trying to break it**: nine probes
against the real binary, each one aimed at a claim the code made about itself.

The lesson generalises. A gate that has never been shown failing is a gate
nobody has tested. Each defect below was in code written to prevent exactly that
defect one level out.

## What Was Wrong

**A claim could name anything.** The subset gate ran over clauses only. A minted
claim calling `(system "echo REACHED-THE-WORLD")` spawned a shell inside the
claim build and printed `ok`. Worse than the reach: `clauselessClaims` checked
that *a* claim with a `.call` existed, not that the call touched the program, so
the newest invariant on the branch ("refuse behaviour nothing observes") was
satisfied by a claim observing nothing. Fixed by one grounding walk shared
between clause and claim, differing only in ground set, plus transitive
reachability from each claim's call into the clauses it runs.

**A deeper clause subject silently shadowed a clause.** `clause.main` and
`clause.main.extra` collapse to the same name. Different subjects, so merge saw
no conflict; both passed the gate; both reached `core.scm`; Guile took the last.
The probe printed `second`.

**A constant satisfied the entry.** `Realize.arityOf` said a constant has arity
0 while `Gate.paramCount` said it has none. Two functions, one question, two
answers. `(define main 5)` passed every gate and the binary died with `Wrong
type to apply: 5` — which is the *same* failure the entry check had been added
to prevent, one level in.

**Claims with no clauses died inside nix**, on a missing `site/build.nix`, with
a remedy that blamed the sentence.

**`(exit claim-failures)`** wraps at 256, so 256 failing claims exit 0.

Three gate defects refused honest clauses: named `let` (every lisp's loop) read
its own name as the binding list; a variadic parameter list counted `.` as a
parameter; and a program word carrying `#<` rendered into a string that read
back as a hole. Guile rejects `\#`, so that last one had to become a refusal —
there is no spelling that both survives the parser and loads.

## The Defect That Cost the Most

Two re-mints, 23 and 35 minutes, were refused for this line:

> I now have a fully verified engine. Here is the final answer.

The prompt says "Output ONLY lines of these forms, no prose". The model added a
closing sentence anyway, twice, and the reply parser read it as a malformed
item. The strictness is right — a line that might be an item the model meant
must never be dropped — so the fix is a stated rule, not a loosening: **prose is
a line whose first token is not a confidence AND whose first three tokens hold
no item keyword**. `O.9 p1 pattern ...` still fails loud, because `pattern` is
right there. An empty reply became an error of its own, since with prose ignored
a model answering in sentences alone would otherwise have materialised a
language that reads nothing.

After this, mint times dropped from 23–35 minutes to 6–10.

## What the Exact Check Found

Turning "some claim exists" into "every clause is reached" immediately failed
three of the six committed validation scenarios. All three were genuine:
`tally` never ran `main`; the `logscan` scenario and `report` claimed only pure
helpers. The programs' actual top-level behaviour — reading stdin, printing —
was unobserved, and a re-mint could have rewritten it invisibly.

`report` then refused twice more, correctly, for a reason worth keeping: its
sentence said "the ten most common", and no small example distinguishes top-ten
from top-anything. The mint filed `missing-witness` rather than faking a claim.
**A top-N program needs a witness that excludes something**; the program was
changed to "the two most common" with an example of three distinct lines, and
minted clean.

## Evidence

- Suite 716 → 732 examples, `-Wall` clean.
- Corpus: 21 programs, 0 failures, host binary and packaged binary alike.
- `nix flake check` green; `check-expect` green over the packaged binary.
- Validation: 8 scenarios, 41 cases, 0 failures — up from 6 and 36.
- Two brand-new programs (`redact`, `chunk`) minted with sonnet passed every
  gate on the first attempt, and both chose `(begin (main) (emitted))` without
  being shown those scenarios.

## What Did Not Change

The idea. Serializer-not-translator still holds, and every fix here was inside
that frame rather than against it. The kernel now holds fewer words of Scheme
than before, not more: the claim protocol joined the defining word in the
runtime's own declaration, and runtimes are discovered as directories rather
than listed in code.

## Open

- `Contract` arity is a plain `Int` with no variadic form. Nothing needs one
  yet; `apply` is in the vocabulary, so the day something does, the shape is
  expressible without a kernel change.
- The nine contracts still serve stdin→stdout only. Files and clocks remain the
  boundary, and the remedy remains adopting WIT/WASI rather than inventing
  ad-hoc contracts (recorded 2026-08-04, unchanged).
