# Logic Axis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a program's behavior live in minted clauses that are decisions,
emitted as a safe subset of Scheme, so every line of logic names the program
line that caused it and runs on any runtime whose adapters cover its contracts.

**Architecture:** A clause is a decision (`clause.<name>` with an s-expression
assertion), so provenance, merge and refinement come for free. The kernel gains
a closed s-expression value form it never evaluates, exactly as it gains Nix
values it never evaluates. A vocabulary file (data, shipped as an asset) tells a
domain-blind gate which identifiers are grounded; anything else is a mint defect.
Adapters bind contracts by name at link time, so one clause set runs on several
runtimes with no re-mint.

**Tech Stack:** Haskell (kernel, `-Wall` clean, hspec), Nix (substrate and
build), Guile 3 (first runtime), guile-json (first pure adapter package).

## Status, and Where the Plan Was Corrected in Flight

All ten tasks are landed and green (690 examples, 0 failures, `-Wall` clean across
library, app and suite). Task 7 is proved end to end by
`experiments/clause-site/`: `lips compile` writes the site and
`printf 'a\nb\nc\n' | nix run 'path:...#site'` prints the three lines. Its engine
is hand-written, because no mint emits clauses until Task 9.

Task 10 landed as SHAPE ONLY, deliberately. A site is now named
(`site.<name>.command`, `site.<name>.property.<p>`) and its stated properties feed
the covering, so which runtime runs the behaviour is a computation over
requirements exactly as intended. What is NOT built is several sites at once: two
is a loud refusal rather than a silent choice. No committed example needs a second
place, so building per-site directories now would be speculative machinery, and
the refusal makes growing to several a kernel change nobody can stumble into.

Task 9 also cost four bugs found by live mints and fixed with regression tests
(clauses rendered into the module; the site binding decided from option values
only, missing a reference from an artifact argument; `claims.nix` needing the same
binding; every gate's temp directory needing the site staged beside the module).
Falsifier check (c) is still unanswered: see `TODO.md` item 11.

Task 8 landed as a SEPARATE type, `ClauseClaim`, rather than as variants of
`Claim`: the two are observed by different machinery (a process through its
stdin, versus an expression), so keeping them apart makes a claim that is half
command and half expression unrepresentable. It is judged by
`nix build ...#site-claims`, a small derivation that evaluates the core with the
runtime's list-backed adapters and its verdict harness; a failed claim exits
nonzero, so the build fails. `lips check` runs it in about a second, against
minutes for a `buildGoModule` claim, and it can observe one definition rather
than a whole process. Also landed: `Rungs`, a record replacing what had become
four positional booleans in `flakeText`.

Two things Task 7 forced, both keeping host knowledge out of the kernel: a
runtime now declares its ENTRY expression (`entry (main (cdr (command-line)))`,
so lips never learns that Guile spells it `command-line`) and its BUILDER
(`build site.nix`, a Nix file taking `{ pkgs, name, src }` that lips copies and
calls). And `realizeClauses` takes the SOURCE base beside the ground one, since a
minted clause is derived from a program decision that refine removes before
realize, so the ground base alone cannot say which line caused it. Two things landed that the plan did not ask for, and
both belong to whoever runs the rest:

- **`Lips.Kernel.Grounding`**, which counts what vouches for each assertion and
  names what nothing does, printed on every `lips check`. It measured the corpus
  before any migration (see the learnings doc), which is what the no-blob
  doctrine will be argued from.
- **Clause holes participate in word typing**, since main gained that feature
  while this branch was open: a typed hole in a clause labels its word for the
  LSP exactly as an option value does.

Seven things turned out differently than written, and the plan is corrected here
rather than left to mislead whoever runs Tasks 7 to 10:

- **The hole marker inside a clause is `#<value:int>`, not `<value:int>`.** `<`
  and `>` are ordinary Scheme identifier characters, so a clause must be able to
  write `(< n 3)`. `#<...>` is reserved notation in Scheme, which reads exactly
  right: unreadable until filled.
- **`HoleType` moved to `kernel/src/Lips/Kernel/Hole.hs`**, imported by both value
  grammars, so `<value:int>` cannot come to mean two things. `Value` re-exports
  it, so no caller changed.
- **`Sexp` exports `parseSexpPrefix`** beside `parseSexp`, because the value
  grammar parses a clause out of the middle of a larger text.
- **Tests live in the existing monolithic `kernel/test/Spec.hs`**, not in new
  spec files: that is the suite's pattern. `Lips.Kernel.Sexp` is imported
  qualified as `Sx` there, since `Lips.Kernel.Lang.Pattern` already owns the
  names `SLit` and `SHole`.
- **`cover` is called `coveringRuntime`**, because `Test.QuickCheck` exports a
  `cover` the suite imports.
- **The clause vocabulary is injected into `runBase`**, not imported by the
  kernel, and `Realization` gained `rlCore` and `rlGrounding`. So `compile`
  already writes `core.scm`; Task 7 is the adapters, the entry point and the
  derivation around them.
- **The shipped vocabulary and catalogue load in a new tier,
  `kernel/src/Lips/Runtime.hs`**, which embeds the assets and hands the kernel a
  `Vocabulary` and a `[Runtime]`. The kernel stays a reader; what lips happens to
  ship is this module's decision.

## Global Constraints

- The kernel knows nothing about any program, language or runtime. Every
  concrete name (a binding form, a base procedure, a contract, a package)
  arrives as data from a vocabulary or catalogue file, never as a kernel branch.
- The kernel never evaluates a clause. Claims run on the real runtime, so the
  checked object and the run object stay identical (decision doc §12).
- The suite and app stay `-Wall` clean. `just test` is the fast gate; `just ci`
  before a merge.
- Nix flakes see only git-tracked files: `git add` before any `nix build`.
- Single-line commits, no merge commits, no attribution trailers.
- Illegal states unrepresentable: the s-expression grammar is closed, has no
  constructor for a raw text escape, and fills holes through the same escaping
  discipline `fillValue` already uses.
- Work happens in `.worktrees/logic-axis`, branched from `main`.

## Prior Work This Builds On

`experiments/logscan-clauses/` is the hand-run falsifier and the reference for
every artifact this plan produces: `clauses.scm` (what a mint must emit),
`contracts.scm` (the declaration), `adapter-*.scm` (the link targets),
`gate.scm` (what Task 4 reimplements in Haskell), `claims.scm` (what Task 9
generates). Read it before starting. Findings and numbers:
`docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`.

## File Structure

**New kernel modules**

- `kernel/src/Lips/Kernel/Sexp.hs` — the closed s-expression grammar, its
  parser, its canonical renderer, and hole filling. No evaluation, ever.
- `kernel/src/Lips/Kernel/Clause/Vocabulary.hs` — the vocabulary type and its
  file parser: binding forms with binder positions, base procedures, contracts.
- `kernel/src/Lips/Kernel/Clause/Gate.hs` — free-identifier and provenance
  checks over a clause set, given a vocabulary.
- `kernel/src/Lips/Kernel/Clause/Catalogue.hs` — runtimes, what each provides,
  what properties each has, and the covering computation.

**Modified kernel modules**

- `kernel/src/Lips/Kernel/Engine/Value.hs` — add `VSexp`.
- `kernel/src/Lips/Kernel/Realize.hs` — assemble `clause.*` decisions into a
  core file and link a runtime's adapters.

**New assets (data, embedded at build time, reviewable)**

- `assets/runtime/scheme/vocabulary` — base forms, base procedures.
- `assets/runtime/scheme/contracts` — the contract declarations.
- `assets/runtime/guile/adapter-pure.scm`, `adapter-effects.scm`,
  `adapter-effects-memory.scm`, `runtime` (its catalogue entry).

**Tests**

- `kernel/test/SexpSpec.hs`, `ClauseGateSpec.hs`, `ClauseCatalogueSpec.hs`,
  and additions to the realize spec.

---

### Task 1: The Closed S-Expression Grammar

**Files:**
- Create: `kernel/src/Lips/Kernel/Sexp.hs`
- Test: `kernel/test/SexpSpec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Engine.Value` (`HoleType`, `parseHoleType`) for holes.
- Produces:
  ```haskell
  data SExp
    = SSym Text          -- an identifier: the ONLY way a clause names anything
    | SStr Text          -- a string literal
    | SInt Integer
    | SFloat Double
    | SBool Bool
    | SList [SExp]
    | SQuote SExp        -- 'x, the one abbreviation; data, never a call
    | SHole HoleType Text -- <value:int>, filled from a program value
    deriving (Eq, Show)

  parseSexp   :: Text -> Either Text SExp
  renderSexp  :: SExp -> Text
  fillSexp    :: (Text -> Either Text Text) -> SExp -> Either Text SExp
  sexpSymbols :: SExp -> [Text]   -- every symbol, in order, duplicates kept
  ```

- [ ] **Step 1: Write the failing tests**

```haskell
-- kernel/test/SexpSpec.hs
spec :: Spec
spec = describe "Sexp" $ do
  it "round-trips a clause" $ do
    let t = "(define (keep? r s) (cond ((null? s) #t) (else #f)))"
    fmap renderSexp (parseSexp t) `shouldBe` Right t

  it "reads a quoted empty list as data" $
    parseSexp "'()" `shouldBe` Right (SQuote (SList []))

  it "refuses text left over after the expression" $
    parseSexp "(a) (b)" `shouldSatisfy` isLeft

  it "refuses an unclosed list naming what was rejected" $
    parseSexp "(define (f" `shouldSatisfy` isLeft

  it "fills a typed hole with a program value" $
    fmap renderSexp (fillSexp (const (Right "14")) (SHole HInt "value"))
      `shouldBe` Right "14"

  it "refuses a hole filled with something of the wrong type" $
    fillSexp (const (Right "daily")) (SHole HInt "value") `shouldSatisfy` isLeft

  it "escapes a program value landing in a string, so it cannot end the string" $
    fmap renderSexp (fillSexp (const (Right "a\"b")) (SStr "<value>"))
      `shouldBe` Right "\"a\\\"b\""

  it "lists every symbol it mentions" $
    fmap sexpSymbols (parseSexp "(f (g x) 1 \"s\")")
      `shouldBe` Right ["f", "g", "x"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: compile failure, `Lips.Kernel.Sexp` not found.

- [ ] **Step 3: Implement the grammar**

Mirror `Lips.Kernel.Engine.Value`'s shape: a hand-written recursive-descent
parser returning `Either Text (SExp, Text)`, a total renderer, and a filler that
routes every hole through the same coercion discipline `fillValue` uses. Two
rules the module header must state and the code must enforce: a symbol is the
only way a clause names anything (so the gate has exactly one thing to check),
and there is no constructor for raw text, so a program value cannot become code.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green, no warnings.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Sexp.hs kernel/test/SexpSpec.hs
git commit -m "kernel: the closed s-expression grammar, never evaluated"
```

---

### Task 2: S-Expressions as Rule Right-Hand Sides

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Value.hs`
- Test: extend `kernel/test/SexpSpec.hs` with a `Value` section

**Interfaces:**
- Consumes: `Lips.Kernel.Sexp` from Task 1.
- Produces: `Value` gains `VSexp SExp`. `parseValue` reads it when the text
  starts with `(` or `'`; `renderValue` and `renderRealized` serialize it;
  `fillValue` recurses into it; `valueUsesAssertion` and `valueCaptures` see its
  holes.

- [ ] **Step 1: Write the failing tests**

```haskell
  it "parses an s-expression rhs" $
    parseValue "(define (limit) <value:int>)"
      `shouldSatisfy` either (const False) (\v -> case v of VSexp _ -> True; _ -> False)

  it "round-trips an s-expression rhs through the canonical form" $ do
    let t = "(define (limit) <value:int>)"
    fmap renderValue (parseValue t) `shouldBe` Right t

  it "reports the assertion hole inside an s-expression" $
    fmap valueUsesAssertion (parseValue "(define (limit) <value:int>)")
      `shouldBe` Right True

  it "still refuses a bare identifier as a whole rhs" $
    parseValue "pkgs.curl" `shouldSatisfy` isLeft
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: FAIL, `VSexp` not a constructor.

- [ ] **Step 3: Add the constructor and wire every total function**

`Value` has nine call sites that pattern-match exhaustively (`sourceText`,
`valueRefsDerivation`, `valueArtifactNames`, `valueArtifactPaths`, `valuePaths`,
`bindSelfValue`, `bindCaptureValue`, `valueCaptures`, `valuePathHoles`,
`valueUsesAssertion`, `renderValue`, `renderRealized`, `fillValue`). `-Wall`
turns each omission into a warning, so compile first and let the warnings drive
the edit. `sourceText` returns `Nothing` for `VSexp` (an s-expression has no
plain text form).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green, zero warnings.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Value.hs kernel/test/SexpSpec.hs
git commit -m "kernel: an s-expression is a value, so a clause can be a rule's rhs"
```

---

### Task 3: The Vocabulary, as Data

**Files:**
- Create: `kernel/src/Lips/Kernel/Clause/Vocabulary.hs`
- Create: `assets/runtime/scheme/vocabulary`
- Create: `assets/runtime/scheme/contracts`
- Test: `kernel/test/ClauseGateSpec.hs` (vocabulary section)

**Interfaces:**
- Produces:
  ```haskell
  data Binder = Binder { bForm :: Text, bParams :: BinderShape }
  data BinderShape = ParamsAt Int | BindingsAt Int  -- (lambda ARGS body) | (let BINDINGS body)
  data ContractKind = Pure | Effect deriving (Eq, Show)
  data Contract = Contract { cName :: Text, cArity :: Int, cKind :: ContractKind, cDoc :: Text }
  data Vocabulary = Vocabulary
    { vBinders    :: [Binder]
    , vForms      :: [Text]      -- non-binding special forms: cond, if, or, and, else, quote
    , vProcedures :: [Text]      -- base procedures present on every runtime
    , vContracts  :: [Contract]
    }
  parseVocabulary :: Text -> Either Text Vocabulary
  parseContracts  :: Text -> Either Text [Contract]
  ```

The asset files are line-oriented, one declaration per line, mirroring the
`.lang` style so a reviewer reads one grammar everywhere:

```
# assets/runtime/scheme/vocabulary
binder lambda params 1
binder let bindings 1
binder let* bindings 1
binder letrec bindings 1
form cond
form else
form if
form or
form and
form quote
procedure cons 2
procedure car 1
procedure cdr 1
procedure null? 1
procedure equal? 2
```

```
# assets/runtime/scheme/contracts
pure json-parse 1 "text -> record, or #f when the text is not JSON"
pure string-cut 2 "text char -> (before . after) at the first char, or #f"
pure field-of 2 "record name -> the field's value, or #f when absent"
effect read-a-line 0 "-> the next input line, or the end-of-input value"
effect end-of-input? 1 "x -> whether x is the end-of-input value"
effect emit 1 "line -> writes it to the output, followed by a newline"
effect die 2 "message subject -> stops the program, naming the subject"
```

- [ ] **Step 1: Write the failing tests**

```haskell
  it "reads a binder with its parameter position" $
    fmap vBinders (parseVocabulary "binder lambda params 1")
      `shouldBe` Right [Binder "lambda" (ParamsAt 1)]

  it "reads a contract with its kind and arity" $
    parseContracts "effect emit 1 \"line -> writes it\""
      `shouldBe` Right [Contract "emit" 1 Effect "line -> writes it"]

  it "ignores comments and blank lines" $
    fmap vForms (parseVocabulary "# a comment\n\nform cond\n")
      `shouldBe` Right ["cond"]

  it "fails loud on an unknown declaration, naming the line" $
    parseVocabulary "wobble lambda" `shouldSatisfy` isLeft
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement the parsers and write the asset files**

Both parsers are line splits with a loud `Left` naming the offending line and
what was expected. Write the two asset files exactly as shown above, extending
`procedure` lines to cover what `experiments/logscan-clauses/clauses.scm`
actually uses.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Clause/Vocabulary.hs assets/runtime/scheme kernel/test/ClauseGateSpec.hs
git commit -m "kernel: the scheme vocabulary is data the kernel reads, not a branch it holds"
```

---

### Task 4: The Subset Gate

**Files:**
- Create: `kernel/src/Lips/Kernel/Clause/Gate.hs`
- Test: `kernel/test/ClauseGateSpec.hs` (gate section)

**Interfaces:**
- Consumes: `Sexp` (Task 1), `Vocabulary` (Task 3), `Decision` for provenance.
- Produces:
  ```haskell
  data Clause = Clause { clName :: Text, clBody :: SExp, clFrom :: [SourceLoc] }
  data GateFault
    = Ungrounded Text Text     -- clause name, identifier
    | Unprovenanced Text       -- clause name
    | NotADefinition Text      -- clause name: the body is not (define (name ...) ...)
    deriving (Eq, Show)
  gate :: Vocabulary -> [Clause] -> [GateFault]
  reachedContracts :: Vocabulary -> [Clause] -> [Contract]
  ```

`reachedContracts` is the program's reach, and Task 7 covers it against a
runtime. The reference implementation to port is
`experiments/logscan-clauses/gate.scm`, which already proved the walk on the
real corpus (8 clauses, 4 effect contracts, 0 faults; seeded with `system` and a
missing provenance comment it named all three offenders).

- [ ] **Step 1: Write the failing tests**

```haskell
  it "passes the logscan core" $
    gate scheme logscanClauses `shouldBe` []

  it "names an identifier no vocabulary grounds" $
    gate scheme [clauseFrom "sneaky" "(define (sneaky p) (system p))"]
      `shouldBe` [Ungrounded "sneaky" "system"]

  it "does not report a lambda parameter as ungrounded" $
    gate scheme [clauseFrom "f" "(define (f xs) ((lambda (y) y) xs))"] `shouldBe` []

  it "does not report a let binding as ungrounded" $
    gate scheme [clauseFrom "f" "(define (f xs) (let ((y xs)) y))"] `shouldBe` []

  it "does not look inside quoted data" $
    gate scheme [clauseFrom "f" "(define (f) '(system))"] `shouldBe` []

  it "sees a clause calling another clause as grounded" $
    gate scheme [ clauseFrom "a" "(define (a x) (b x))"
                , clauseFrom "b" "(define (b x) x)" ] `shouldBe` []

  it "reports a clause with no provenance" $
    gate scheme [clauseNoWhere "f" "(define (f x) x)"] `shouldBe` [Unprovenanced "f"]

  it "reports the contracts the core reaches, and nothing more" $
    map cName (reachedContracts scheme logscanClauses)
      `shouldBe` ["die", "emit", "end-of-input?", "json-parse", "read-a-line", "string-cut"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement the walk**

One traversal carrying a bound-name set. A symbol is grounded when it is bound,
a form, a procedure, a contract, or another clause's name. `SQuote` terminates
the walk (data, not code). A binder extends the bound set from its declared
parameter position. Provenance is a field on `Clause`, not a comment, because a
clause is a decision and a decision already carries provenance; the emitted file
prints it as a comment for the human.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Clause/Gate.hs kernel/test/ClauseGateSpec.hs
git commit -m "kernel: the subset gate, so a clause reaches the world only by contract"
```

---

### Task 5: Clauses Are Decisions, and Realize Assembles Them

**Files:**
- Modify: `kernel/src/Lips/Kernel/Realize.hs`
- Test: extend the realize spec

**Interfaces:**
- Consumes: `Clause`, `gate` (Task 4).
- Produces:
  ```haskell
  realizeClauses :: Base -> Either RealizeError (Maybe Text)
  ```
  Collects every `clause.<name>` decision, orders them by provenance
  (`(file,line)` first, derived after, the order `assembleSubject` already
  uses), renders each as `;; @from <file>:<line>` followed by the body, and
  returns the core file text. `Nothing` when the program has no clauses, so an
  existing config-only program is untouched.

- [ ] **Step 1: Write the failing test**

```haskell
  it "assembles clause decisions into a core file, in source order, with provenance" $ do
    let base = baseFrom
          [ "c2 meta clause.keep stated \"(define (keep? x) x)\" @p.lips:2"
          , "c1 meta clause.main stated \"(define (main a) (keep? a))\" @p.lips:1" ]
    realizeClauses base `shouldBe` Right (Just
      ";; @from p.lips:1\n(define (main a) (keep? a))\n\n\
      \;; @from p.lips:2\n(define (keep? x) x)\n")

  it "returns nothing for a program with no clauses" $
    realizeClauses configOnlyBase `shouldBe` Right Nothing

  it "refuses a core whose clause reaches an ungrounded name" $
    realizeClauses sneakyBase `shouldSatisfy` isLeft
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: FAIL, `realizeClauses` not defined.

- [ ] **Step 3: Implement**

Reuse the `Subject ("clause" : name : _)` pattern match style already used for
`artifact` and `claim` heads in `Realize.hs`. Run `gate` before returning and
map every `GateFault` into the existing `RealizeError` sum, so a mint defect
fails at realize with the offender named.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Realize.hs kernel/test
git commit -m "kernel: realize assembles clause decisions into one gated core"
```

---

### Task 6: The Runtime Catalogue and Its Adapters

**Files:**
- Create: `kernel/src/Lips/Kernel/Clause/Catalogue.hs`
- Create: `assets/runtime/guile/runtime`, `adapter-pure.scm`,
  `adapter-effects.scm`, `adapter-effects-memory.scm`
- Test: `kernel/test/ClauseCatalogueSpec.hs`

**Interfaces:**
- Produces:
  ```haskell
  data Runtime = Runtime
    { rName       :: Text
    , rProperties :: [Text]     -- native, fast-start, browser, jvm-interop
    , rProvides   :: [Text]     -- contract names
    , rPackages   :: [Text]     -- nixpkgs attribute paths the adapters need
    , rFiles      :: [FilePath] -- adapter files, linked in this order
    }
  parseRuntime :: Text -> Either Text Runtime
  cover :: [Runtime] -> [Text] -> [Text] -> Either Text Runtime
  -- cover runtimes neededContracts requiredProperties
  ```

`cover` is total and never guesses: no candidate is a `Left` naming the first
missing contract or property and the runtimes that came closest; several
candidates is a `Left` listing them, because an author adding one requirement is
cheaper than lips picking wrong.

The guile adapter files are copied verbatim from
`experiments/logscan-clauses/`, which are already proven to run the corpus.

```
# assets/runtime/guile/runtime
property native
property fast-start
provides json-parse string-cut field-of read-a-line end-of-input? emit die
package guile
package guile-json
file adapter-pure.scm
file adapter-effects.scm
```

- [ ] **Step 1: Write the failing tests**

```haskell
  it "picks the one runtime covering the contracts and the properties" $
    cover [guile, hoot] ["emit", "json-parse"] ["native"] `shouldBe` Right guile

  it "fails naming the missing contract when nothing covers" $
    cover [guile] ["talk-to-serial-port"] []
      `shouldSatisfy` either (T.isInfixOf "talk-to-serial-port") (const False)

  it "fails naming the missing property when nothing covers" $
    cover [guile] ["emit"] ["browser"]
      `shouldSatisfy` either (T.isInfixOf "browser") (const False)

  it "fails listing the candidates when several cover, rather than choosing" $
    cover [guile, hoot] ["emit"] []
      `shouldSatisfy` either (\e -> T.isInfixOf "guile" e && T.isInfixOf "hoot" e)
                             (const False)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement and copy the adapters**

```bash
cp experiments/logscan-clauses/adapter-pure.scm assets/runtime/guile/
cp experiments/logscan-clauses/adapter-effects-guile.scm assets/runtime/guile/adapter-effects.scm
cp experiments/logscan-clauses/adapter-effects-memory.scm assets/runtime/guile/
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Clause/Catalogue.hs assets/runtime/guile kernel/test/ClauseCatalogueSpec.hs
git commit -m "kernel: the runtime catalogue, and covering that fails rather than guesses"
```

---

### Task 7: Compile Emits a Runnable Site

**Files:**
- Modify: the compile path that writes the module directory (follow
  `artifactEntries` in `kernel/src/Lips/Kernel/Realize.hs` and the flake writer)
- Test: extend the realize spec, plus a shell check against `examples/`

**Interfaces:**
- Consumes: `realizeClauses` (Task 5), `cover` (Task 6).
- Produces: for a program with clauses, the compiled directory gains
  `core.scm`, the chosen runtime's adapter files, `main.scm` (adapters, then
  core, then the entry call), and an `artifact.<name>` derivation wrapping them
  with the runtime's packages.

- [ ] **Step 1: Write the failing test**

```haskell
  it "writes a site whose main.scm links adapters before the core" $ do
    files <- compileToTemp "examples/logscan.lips"
    lookup "main.scm" files `shouldSatisfy`
      maybe False (\t -> "adapter-pure.scm" `T.isInfixOf` t
                      && T.isInfixOf "core.scm" t)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just test`
Expected: FAIL, no `main.scm` written.

- [ ] **Step 3: Implement the assembly**

Mirror `experiments/logscan-clauses/logscan.scm` exactly: load adapters in
catalogue order, load the core, call the entry. The derivation names the
runtime's packages by attribute path, so the kernel still reaches concrete
things only by name.

- [ ] **Step 4: Verify end to end**

```bash
git add examples && lips compile examples/logscan.lips
printf '{"a":"1"}\n{"a":"2"}\n' | nix run path:examples/logscan/out/logscan#artifact.logscan -- a=1
```
Expected: `{"a":"1"}` and nothing else.

- [ ] **Step 5: Commit**

```bash
git add kernel/src examples kernel/test
git commit -m "compile: emit a runnable site, adapters linked to the gated core"
```

---

### Task 8: Clause Claims, Offline

**Files:**
- Modify: `kernel/src/Lips/Kernel/Claim.hs`
- Test: extend the claim spec

**Interfaces:**
- Produces: a third `ClaimPlace`, `PlaceClauses`, derived like the other two and
  never declared: a claim whose `call` names only clause names runs under the
  memory adapter, with no derivation and no boot. New closed sections
  `claim.<id>.call`, `claim.<id>.equals`, `claim.<id>.feed`.

- [ ] **Step 1: Write the failing tests**

```haskell
  it "runs a claim naming only clauses in the clause place" $
    claimPlace claimOverKeep `shouldBe` PlaceClauses

  it "keeps a claim naming an artifact in the derivation place" $
    claimPlace claimOverBinary `shouldBe` PlaceDerivation

  it "renders a claim file that feeds lines and compares the emitted list" $
    renderClauseClaims [claimWitness] `shouldSatisfy` T.isInfixOf "(feed-lines"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL, `PlaceClauses` not a constructor.

- [ ] **Step 3: Implement**

Generate the file `experiments/logscan-clauses/claims.scm` already proves out:
link `adapter-effects-memory.scm` instead of the real one, then one `claim` call
per stated observable.

- [ ] **Step 4: Verify end to end**

```bash
time lips check examples/logscan.lips
```
Expected: every claim green, no `nix build`, well under a second.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Claim.hs kernel/test
git commit -m "claims: a claim over clauses runs offline, with no build and no boot"
```

---

### Task 9: Teach the Mint to Emit Clauses

**Files:**
- Modify: `assets/mint/` (the system prompt), the draft-check tool
- Test: two live mints (below)

**Interfaces:**
- Consumes: the gate (Task 4) through `lips check --draft`, so a mint that
  reaches an ungrounded name is corrected inside the one call.

- [ ] **Step 1: Add the clause doctrine to the mint prompt**

Three rules, stated in the prompt's existing voice, and no per-problem
knowledge: behavior goes in `clause.<name>` decisions, one definition per thing
the program says; a clause reaches the world only through a declared contract,
and a needed contract that no runtime provides is a demand, never an invention;
every program value inside a clause is a hole, as everywhere else.

- [ ] **Step 2: Mint logscan twice, from the same program**

```bash
lips generate --renew examples/logscan.lips && cp examples/logscan/out/logscan/core.scm /tmp/mint-a.scm
lips generate --renew examples/logscan.lips && cp examples/logscan/out/logscan/core.scm /tmp/mint-b.scm
diff -u /tmp/mint-a.scm /tmp/mint-b.scm
```

- [ ] **Step 3: Record the answer to falsifier check (c)**

Append the diff and its reading to
`docs/superpowers/learnings/2026-08-04-logscan-clause-falsifier.md`. The measured
baseline to beat is the Go axis: two mints there differ in exit code (1 versus 2)
and in whether `{"a":1e-7}` is kept under `a=0.0000001`.

- [ ] **Step 4: Commit**

```bash
git add assets/mint docs examples
git commit -m "mint: emit behaviour as clauses, and record what two mints agree on"
```

---

### Task 10: Sites, So One Core Serves Several Runtimes

**Files:**
- Modify: `kernel/src/Lips/Kernel/Realize.hs`, the compile path
- Test: a two-site example

**Interfaces:**
- Produces: `site.<name>.property.<p>` decisions read from program sentences.
  Coverage runs per site over the same reached contract set, and compile writes
  one directory per site. With no site stated, one site named for the instance
  is implied, so every earlier task keeps working unchanged.

- [ ] **Step 1: Write the failing test**

```haskell
  it "writes one directory per site, sharing one core" $ do
    files <- compileToTemp "examples/check.form.lips"
    map fst files `shouldContain` ["site-browser/main.scm", "site-server/main.scm"]
    lookup "core.scm" files `shouldSatisfy` isJust
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `just test`
Expected: FAIL, one site only.

- [ ] **Step 3: Implement, and add the example**

`examples/check.form.lips` states a rule that must hold in a browser and on a
server. Add a `hoot` runtime entry to the catalogue with `property browser`.

- [ ] **Step 4: Verify both sites**

```bash
git add examples && lips compile examples/check.form.lips
nix build path:examples/form/out/check/site-server#artifact.check
nix build path:examples/form/out/check/site-browser#artifact.check
```

- [ ] **Step 5: Commit**

```bash
git add kernel/src examples kernel/test
git commit -m "sites: one gated core, one directory per place it runs"
```

---

## Self-Review

**Spec coverage.** Clauses as decisions (Tasks 2, 5), the closed grammar
(Task 1), the domain-blind gate with its vocabulary as data (Tasks 3, 4),
contracts and adapters bound by name (Task 6), a runnable site (Task 7),
offline claims (Task 8), the mint and falsifier check (c) (Task 9),
multi-site (Task 10). The open item the plan deliberately does not touch is
open predicates (decision doc §10), which no committed example needs.

**Placeholders.** None: every task names exact files, exact test bodies and
exact commands.

**Type consistency.** `SExp`, `Clause`, `GateFault`, `Vocabulary`, `Contract`,
`Runtime` are defined once and used with the same field names throughout.
`reachedContracts` (Task 4) feeds `cover` (Task 6) feeds Task 7's assembly.

## What Would Kill This Mid-Flight

Stop and report rather than working around, in the spirit of invariant 4:

- The gate needs a case the vocabulary cannot express as data, which would mean
  the kernel learning Scheme rather than reading a vocabulary.
- Two mints of one program produce clause sets differing where the program does
  not (Task 9), which is the falsifier's own failure condition.
- A clause set for a real program grows past the source it replaces, the other
  stated failure condition.
