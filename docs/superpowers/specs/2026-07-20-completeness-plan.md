# Completeness by Construction

Status: planned. Companion to `2026-07-18-lipsidea-design.md`. Resolves a class
of gap reports (first instance: the nginx/http-server program) by making the
kernel's closed grammars complete over their domains, so expressiveness gaps
stop recurring one feature at a time.

## The Principle

The kernel refuses a program for exactly three reasons, and a missing grammar
case is not one of them:

1. **Deduce-or-fail.** The program is genuinely ambiguous or underspecified.
   A program problem, surfaced as an open question.
2. **Computation needed.** The program needs a value computed, not stated.
   Routed to the one documented incompleteness: glue (below).
3. **Reality.** The world will not cooperate (Heile-Welt boundary).

Everything else must be expressible. Each closed grammar is therefore designed
to be **complete over its own domain by construction**, not grown per feature.
Two grammars carry this obligation.

## Target 1: Value Grammar = Nix Value Algebra minus Computation

`Lips.Kernel.Engine.Value` defines what a minted rule may emit as a NixOS
option value. Nix values are a closed, known algebra:

    null | bool | int | float | string | path | list | attrset | function

We exclude `function` on purpose (that is computation, door 2). The value
grammar must cover **all the rest**, and every scalar must be expressible both
as a literal and as a hole filled from a program token. Then a whole class of
gaps (int-typed option, path-typed option, ...) cannot recur.

### Current state (incomplete)

    data Value = VStr [Piece] | VList [Value] | VBool Bool | VInt Integer
    data Piece = PLit Text | PRef [Text] | PHole Text

Holes live only inside strings (`PHole` inside `VStr`), so a program value can
only ever become a Nix string. This is why `types.port` fails: `<value>` can
render `"8080"` (a string), never `8080` (an integer).

### Target state

Extend `Value` to the full scalar algebra plus a typed hole:

    data Value
      = VStr   [Piece]           -- string; may carry <value>/<value.N> holes + ${pkgs...}
      | VList  [Value]
      | VBool  Bool
      | VInt   Integer
      | VFloat Double
      | VPath  Text              -- unquoted Nix path literal (/x, ./x, ../x)
      | VNull
      | VHole  HoleType Text     -- a bare, TYPED hole filled from a program token

    data HoleType = HInt | HBool | HFloat | HPath   -- string holes stay inside VStr

Deferred (YAGNI, expressible otherwise): `VAttr` for freeform attrsets.
Nested attrsets are already expressible as deeper option paths (one `Emit` per
leaf), so a literal attrset value waits for a program that genuinely needs
dynamic keys.

### Surface syntax

A hole outside a string must name its type, so parsing stays deterministic and
round-trips (parse-don't-validate; the type is not guessed):

    <value:int>     <value.2:path>     <value:bool>     <value:float>

Inside a string, `<value>` / `<value.N>` remain string holes, unchanged. The
existing rhs convention is preserved: a rule's rhs is wrapped in one pair of
storage quotes, and inside it is a value. A string rhs looks like
`"\"<value>\""`; an integer rhs looks like `"<value:int>"`.

### Filling and safety

`fillValue` coerces a typed hole's program token into its type and **fails
loud** if it does not parse (matching the existing out-of-range `<value.N>`
behavior; the rewrite channel has no `Either`, so this is an `error`). Coercion
keeps injection closed:

- `HInt` / `HFloat`: parse the whole token as a number; emit a bare numeric
  literal. Only digits (and sign/point) ever reach the output.
- `HBool`: token must be `true` or `false`; emit the keyword.
- `HPath`: token must be a valid Nix path literal (leading `/`, `./`, or `../`;
  no whitespace, `;`, or `${`); emit it unquoted. Anything else fails loud, so
  a path hole cannot inject.

`VStr` string holes keep the existing `escape` path unchanged (quotes,
backslashes, `${` neutralized), so the injection-unrepresentable property still
holds for every value form.

### Touch points

    kernel/src/Lips/Kernel/Engine/Value.hs   -- Value/HoleType, parseValue, renderValue, fillValue
    kernel/src/Lips/Kernel/Engine/Data.hs    -- pick already selects the token; typed holes reuse it
    kernel/src/Lips/Generate/Minting.hs      -- prompt: document typed holes for non-string options
    kernel/test/Spec.hs                       -- round-trip + coercion + loud-fail + int-port repro

## Target 2: Template Grammar = a Small Complete Capture Algebra

`Lips.Kernel.Lang.Pattern` templates bind exactly one whitespace token per
hole and produce one decision per line. This is complete for flat single-token
lines but cannot capture a multi-word value, a quoted span, or a bulleted
block. The capture needs are enumerable; a template built from these matchers
is complete over any flat or one-level-nested human line:

- single-token hole (`THole`, present),
- multi-token hole (binds several tokens up to a following literal or line end),
- quoted-span hole (captures the text inside `"..."`, unquoted),
- one level of block structure (a header line introducing `- item` lines),
  so a decision can carry a list of sub-decisions.

This target is "complete over observed line shapes," not a proof; it is
honestly softer than the value algebra. It is scheduled after value
completeness. The nginx program's `- /hello returns text "world"` line needs
the quoted-span hole and the bullet block.

## Target 3: Glue = the One Documented Incompleteness

"Complete by definition" is only true if computation has a home. When a program
needs a value computed rather than stated, the honest answer is glue: marked,
low-rigor, visible-blast-radius computation authored by the model at generate
time (see design doc, Rigor Allocation and the Artifacts milestone). Until glue
exists, a genuine computation need is a hard refuse with a gap report naming
glue as the route. Glue lands after value completeness (owner decision).

## Milestone Order

1. **Value completeness** (this plan's Target 1). Unblocks the current program
   (int-typed port). Self-contained, low design risk.
2. **Template completeness** (Target 2). Multi-token / quoted-span / block.
3. **Glue** (Target 3). The computation door; closes the definition of
   "complete."

Each lands under the conformance suite; a consumer bumps its flake input and
regenerates, gated by its committed `.expect`.
