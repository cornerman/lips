# List Aggregation (B + C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make list-valued options fully expressive — N lines fold into one list across decisions (B), and one line may carry many items (C) — without any block construct, dictated syntax, or new ordering key on the decision.

**Architecture:** Two domain-blind kernel capabilities. **B** adds an `Append` merge mode (alongside `Replace`), derived from the rule emits (a subject whose rule emits a `VList` rhs appends; the option schema is the authority but lives only at generate time, and `checkEmits` already guarantees a rule's rhs value-shape matches its option type, so the value-shape faithfully reflects the schema at run time — run stays offline). `Append` assembles top-strength contributors by source-line order into one synthetic `VList` decision; replace-across-strengths holds (a stronger list replaces the whole list). **C** adds a template tail hole (binds the rest of a line's tokens) and a value tail hole (a rhs that becomes a `VList` of the program value's tokens). Assembly needs to re-parse contributor assertions as `Value`s, but today Meta assertions are stored with `renderRealized` (bare refs, non-round-trippable). So a prerequisite refactor (**R1**) stores Meta assertions canonically (`renderValue`) and makes `realize` the single canonical→Nix render point; this also completes the round-trip the project prizes and simplifies artifact-ref detection (Value-based, replacing a quote-aware text scanner). Design in `docs/superpowers/specs/2026-07-24-list-aggregation-design.md`.

**Tech Stack:** Haskell (GHC, -Wall), hspec + QuickCheck, single conformance suite `kernel/test/Spec.hs`. Build/test via `just test` (or the ghc one-liner in `kernel/`).

## Global Constraints

- Kernel is domain-blind (AGENTS.md "The Kernel Knows Nothing"): no per-problem branch, no dictated collection syntax, no new ordering key on `Decision`. Order is assembly-only, from `SourceLoc`, scoped to `Append` subjects.
- `run` never calls a model (invariant 1); all changes are deterministic, offline. No nixpkgs in `compile`/`run`/`check` closure (the merge mode is derived from rule emits, never the schema, at run time).
- Deduce-or-fail (invariant 2): an empty tail, a non-`VList` Append contributor, or an unparseable assertion fails loud through a typed channel, never a crash.
- Existing engines realize byte-identically where the new mode does not apply (default `Replace` = today). The realized Nix module output is unchanged for non-aggregating engines.
- Conformance suite stays `-Wall` clean. TDD: failing test first, then implement, then green, then commit. Small single-line commits; rebase + ff-merge (no merge commits). Commit messages short, no co-author attribution.
- `git add` files before any `nix build`/`nix run` (flakes see only git-tracked files).
- Work in a worktree under `.worktrees/` (per AGENTS.md).

---

## File Structure

**New:**
- `kernel/src/Lips/Kernel/Engine/Aggregate.hs` — `MergeMode`, `mergeModeOf` (rule-emit-derived), `assembleSubject` (concat top-strength `VList` contributors into one synthetic decision). Imports `Base`, `Decision`, `Engine.Data` (`MapRule`, `Emit`), `Engine.Value`, `Capture`.

**Modified:**
- `kernel/src/Lips/Kernel/Engine/Value.hs` — `fillValue` renders canonical (`renderValue`, not `renderRealized`); add `VTail` value form (C) and `valueArtifactNames` (for R1 artifact detection).
- `kernel/src/Lips/Kernel/Base.hs` — `resolve` gains `(Subject -> MergeMode)` + assemble function (dependency injection, no `Value` import → no cycle); `ResolveErr` type.
- `kernel/src/Lips/Kernel/Realize.hs` — `assignment` parses assertion → `renderRealized`; artifact detection Value-based; `realize` takes the merge config.
- `kernel/src/Lips/Kernel/Run.hs` — `run`/`runBase` thread the merge config; `RunError` maps assembly failure.
- `kernel/src/Lips/Kernel/Lang/Pattern.hs` — `TplTok` gains `TTail` (C); `matchTemplate` variable-length tail.
- `kernel/src/Lips/Kernel/Lang/Store.hs` — render/parse `TTail`.
- `kernel/app/Main.hs` — `validate` builds the merge config from `edRules` and passes it to `runBase`.
- `kernel/test/Spec.hs` — new conformance tests; update the two R1-affected fixtures.

---

### Task 1: Canonical Meta assertions; realize as the single render point (R1)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Value.hs` (`fillValue`)
- Modify: `kernel/src/Lips/Kernel/Realize.hs` (`assignment`, artifact detection, `RealizeError`)
- Modify: `kernel/test/Spec.hs` (fixtures at lines ~309-328 and ~889)

**Interfaces:**
- Produces: `valueArtifactNames :: Value -> [Text]` (in `Engine.Value`); `realize` still `Base -> Either RealizeError Text` for now (merge config added in Task 4). Meta assertions now hold canonical `renderValue` text (round-trippable: `parseValue (renderValue v) == Right v`).

**Why behavior-preserving:** the realized module output is identical — `realize` now parses each canonical assertion and `renderRealized`s it, producing the same Nix text that `fillValue` used to splice directly. Only the *stored assertion representation* changes (realized → canonical).

- [ ] **Step 1: Write the failing round-trip property for Meta assertions**

In `kernel/test/Spec.hs`, inside the `"value language"` describe block, add:

```haskell
    it "a rendered rhs value round-trips through parseValue (canonical, not realized)" $
      property $ forAll genValue $ \v ->
        parseValue (renderValue v) === Right v
```

This already exists (line ~1210) — confirm it passes today for canonical. The NEW failing assertion: a ref-bearing list rendered by `fillValue` must round-trip. Add after the existing `fillValue` test (~889):

```haskell
    it "fillValue stores a canonical (round-trippable) value, not a realized one" $
      property $ forAll genValue $ \v ->
        case fillValue (const (Right "x")) v of
          Right stored -> parseValue stored === Right (substX v)
          Left _       -> property False
      where
        -- every <value>/<value.N> hole is filled with "x"; the resulting
        -- canonical text must re-parse to the same shape.
        substX (VStr ps)    = VStr (map subP ps)
        substX (VList vs)   = VList (map substX vs)
        substX (VAttr fs)   = VAttr (map (fmap substX) fs)
        substX (VHole _ _)  = VStr [PLit "x"]
        substX (VTail _)    = VList [VStr [PLit "x"]]   -- VTail added in Task 7; use VStr fallback for now if VTail absent
        substX v            = v
        subP (PHole _) = PLit "x"
        subP p         = p
```

(If `VTail` is not yet defined, omit that clause for this task; the property still fails today because `fillValue` returns `renderRealized` for `VRef` lists, e.g. `[ pkgs.curl ]`, which `parseValue` rejects.)

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: the new property FAILS (a `VRef`-in-list `fillValue` output does not re-parse).

- [ ] **Step 2: Make `fillValue` render canonical**

In `kernel/src/Lips/Kernel/Engine/Value.hs`, change the `fillValue` definition from `fmap renderRealized` to `fmap renderValue`, and update its doc comment:

```haskell
-- | Fill holes and render to the CANONICAL form ('renderValue'), so the
-- stored assertion round-trips through 'parseValue' (a ref stays @${pkgs..}@,
-- not a bare @pkgs..@). 'Lips.Kernel.Realize.realize' is the single point that
-- converts canonical to realized Nix ('renderRealized'). @.lang@ persistence
-- uses 'renderValue' directly.
fillValue :: (Text -> Either Text Text) -> Value -> Either Text Text
fillValue pick = fmap renderValue . fillV
```

- [ ] **Step 3: Add `valueArtifactNames`**

In `kernel/src/Lips/Kernel/Engine/Value.hs`, add (parallel to `valueRefsDerivation`, but returning the referenced artifact names):

```haskell
-- | The artifact names a value references (a bare or string-interpolated
-- @${artifact.<name>}@), anywhere inside it. Used by 'realize' to detect a
-- dangling artifact reference: once realize parses each assertion to a
-- 'Value', the references are structural facts, not text to scan.
valueArtifactNames :: Value -> [Text]
valueArtifactNames (VStr ps)  = [ n | PArt n <- ps ]
valueArtifactNames (VList vs) = concatMap valueArtifactNames vs
valueArtifactNames (VAttr fs) = concatMap (valueArtifactNames . snd) fs
valueArtifactNames (VRef (RArt n)) = [n]
valueArtifactNames _          = []
```

Export it from the module's export list.

- [ ] **Step 4: Make `realize` parse + renderRealize each assertion, and detect artifacts via `Value`**

In `kernel/src/Lips/Kernel/Realize.hs`:

(a) Add a new error variant (assembly/parse failures fail loud, never crash):

```haskell
data RealizeError
  = RConflicts [Conflict]
  | RDangling [Text]
  | RBadArtifact Text Text
  | RMalformed Subject Text   -- an assertion that is not a canonical Value
  deriving (Eq, Show)
```

(b) Replace the text-based `artifactRefs` machinery in `renderModule` with Value-based detection. The option decisions' assertions are now canonical `Value` text; parse each once, renderRealize for output, and collect artifact names from the parsed Value:

```haskell
renderModule :: [(Subject, Decision)] -> Either RealizeError Text
renderModule winners = do
  let (arts, opts) = partition (rootedAtArtifact . fst) winners
      defined  = [ n | (Subject ("artifact" : n : _), _) <- arts ]
  -- Parse each option assertion once; a non-Value assertion is an engine defect.
  parsed <- traverse parseOpt opts
  let refs = concatMap (valueArtifactNames . snd) parsed
      dangling = [ r | r <- refs, r `notElem` defined ]
  if not (null dangling)
    then Left (RDangling dangling)
    else do
      entries <- artifactEntries arts
      Right $ T.unlines $
        [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
        , "{ config, lib, pkgs, ... }:"
        ]
          ++ letBlock entries
          ++ ["{"]
          ++ concatMap assignment (sortOn (path . fst) (map (\(s,(v,_)) -> (s,v)) parsed))
          ++ ["}"]
  where
    parseOpt (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Right v  -> Right (s, (d, v))
      Left e   -> Left (RMalformed s e)
```

(c) Update `assignment` to take the parsed `Value` and renderRealize it:

```haskell
-- | One option assignment, provenance comment + the realized value text.
assignment :: (Subject, Decision) -> [Text]
assignment (subj, d) =
  [ "  # " <> provComment (dProv d)
  , "  " <> path subj <> " = " <> renderRealizedV (dAssertion d) <> ";"
  ]
  where renderRealizedV (Assertion a) = either (\e -> error ("realize: unparseable " <> T.unpack e)) id (renderRealized <$> parseValue a)
```

NOTE: `assignment` receives the already-parsed pair in `renderModule`'s map; to keep the diff small, pass the `Value` through. Prefer threading the parsed `Value` explicitly rather than re-parsing in `assignment` — refactor `assignment` to `(Subject, Decision, Value)`:

```haskell
renderModule ... ++ concatMap assignment (sortOn (path . \1of3) parsed) ...
  where parsed :: [(Subject,(Decision,Value))]
assignment (subj, d, v) =
  [ "  # " <> provComment (dProv d)
  , "  " <> path subj <> " = " <> renderRealized v <> ";"
  ]
```
Adjust `renderModule` to build `[(Subject,(Decision,Value))]` and feed `assignment`.

(d) Delete the old text-scanner `artifactRefs` function entirely (it is replaced by `valueArtifactNames` over parsed `Value`s). Keep `rootedAtArtifact`, `letBlock`, `artifactEntries`, `builderOf`, `path`, `quoteSeg`, `provComment`.

(e) `artifactEntries` and `builderOf` already `parseValue` their assertions — they continue to work because artifact builder/arg assertions are canonical `Value` text (strings, paths). No change needed there, but verify `builderOf`'s `parseValue a` still yields `VStr [PLit p]`.

- [ ] **Step 5: Update the two R1-affected test fixtures**

In `kernel/test/Spec.hs`:

(a) The `fillValue` bare-ref test (~line 889):

```haskell
      fillValue (const (Right "x")) (VList [VRef (RArt "weather")]) `shouldBe`
        Right "[ ${artifact.weather} ]"
```

(b) The artifact-detection block (~309-328). Bare refs no longer arise in Meta assertions (the model/`fillValue` always emits canonical `${...}`). Rewrite to canonical forms and Value-based reasoning:

```haskell
    it "detects an artifact reference in a canonical list and flags it dangling if unbuilt" $ do
      let built =
            [ (mk "b" "x" "\"buildGoModule\"" Stated) { dSubject = Subject ["artifact","weather","builder"] }
            , (mk "p" "x" "\"weather\"" Stated) { dSubject = Subject ["artifact","weather","args","pname"] }
            , (mk "e" "x" "[ ${artifact.weather} ]" Stated) { dSubject = Subject ["environment","systemPackages"] }
            ]
      realize (fromList built) `shouldSatisfy` isRight
      let dangling = [ (mk "e" "x" "[ ${artifact.ghost} ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realize (fromList dangling) `shouldBe` Left (RDangling ["ghost"])
    it "a literal 'artifact.' token inside a string is not a reference" $
      let litText = [ (mk "e" "x" "\"see artifact.ghost docs\"" Stated) { dSubject = Subject ["environment","variables","NOTE"] } ]
       in realize (fromList litText) `shouldSatisfy` isRight
    it "a package ref whose own segment is 'artifact' is a package, not an artifact" $ do
      let pkgPath = [ (mk "e" "x" "${pkgs.foo.artifact.bar}" Stated) { dSubject = Subject ["services","x","package"] } ]
      realize (fromList pkgPath) `shouldSatisfy` isRight
      let pkgList = [ (mk "e" "x" "[ ${pkgs.foo.artifact.bar} ]" Stated) { dSubject = Subject ["environment","systemPackages"] } ]
      realize (fromList pkgList) `shouldSatisfy` isRight
```

(c) Remove the now-stale `"detects a bare artifact.<name> reference used as a list element"` test body (its premise — a bare ref in an assertion — no longer holds).

- [ ] **Step 6: Run the full suite; confirm module-text tests stay green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS. The module-text expectations (lines ~250-300, ~1064-1080) are unchanged because `renderRealized` produces identical Nix. The new round-trip property passes.

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Value.hs kernel/src/Lips/Kernel/Realize.hs kernel/test/Spec.hs
git commit -m "realize: canonical Meta assertions, Value-based artifact detection"
```

---

### Task 2: MergeMode, mode derivation, and list assembly (Aggregate module)

**Files:**
- Create: `kernel/src/Lips/Kernel/Engine/Aggregate.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `data MergeMode = Replace | Append`; `mergeModeOf :: [MapRule] -> Subject -> MergeMode`; `assembleSubject :: [Decision] -> Either Text Decision`.

- [ ] **Step 1: Write the failing tests**

In `kernel/test/Spec.hs`, add a new describe block:

```haskell
  describe "list aggregation (B: Append merge mode)" $ do
    let pkgs = Subject ["environment","systemPackages"]
        -- two Stated contributors, canonical VList assertions, ordered by line
        d1 = (mk "d1" "x" "[ \"htop\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
        d2 = (mk "d2" "x" "[ \"ripgrep\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
        rule = MapRule "r" Fact ["pkg"] [ Emit ["environment","systemPackages"] (VList [VStr [PHole "value"]]) ]

    it "mergeModeOf: a subject a rule emits a VList to is Append; else Replace" $ do
      mergeModeOf [rule] (Subject ["environment","systemPackages"]) `shouldBe` Append
      mergeModeOf [rule] (Subject ["pkg"]) `shouldBe` Replace
    it "mergeModeOf: a capture-bearing emit path matches a concrete subject" $ do
      let r2 = MapRule "r2" Fact ["grp"] [ Emit ["g","<name>","items"] (VList [VStr [PHole "value"]]) ]
      mergeModeOf [r2] (Subject ["g","key1","items"]) `shouldBe` Append

    it "assembleSubject concatenates VList contributors in source-line order" $
      case assembleSubject [d2,d1] of          -- given out of order
        Right synth -> dAssertion synth `shouldBe` Assertion "[ \"ripgrep\" \"htop\" ]"
        Left e      -> expectationFailure ("assemble failed: " <> show e)
    it "assembleSubject preserves package refs across contributors" $ do
      let a = (mk "a" "x" "[ ${pkgs.curl} ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
          b = (mk "b" "x" "[ ${pkgs.htop} ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
      case assembleSubject [a,b] of
        Right synth -> dAssertion synth `shouldBe` Assertion "[ ${pkgs.curl} ${pkgs.htop} ]"
        Left e      -> expectationFailure ("assemble failed: " <> show e)
    it "assembleSubject fails loud on a non-VList contributor" $
      let bad = (mk "b" "x" "\"not-a-list\"" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
       in assembleSubject [bad] `shouldSatisfy` isLeft
    it "assembleSubject provenance links all contributors (walkable)" $
      case assembleSubject [d1,d2] of
        Right synth -> dProv synth `shouldBe` Derived [DecisionId "d2", DecisionId "d1"] (RuleId "append")
        Left e      -> expectationFailure ("assemble failed: " <> show e)
```

Add `import Lips.Kernel.Engine.Aggregate (MergeMode (..), mergeModeOf, assembleSubject)` to the imports.

Run the suite; expect the new tests to FAIL to compile (`Aggregate` module missing).

- [ ] **Step 2: Create the Aggregate module**

`kernel/src/Lips/Kernel/Engine/Aggregate.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
-- | List aggregation: the Append merge mode and the assembly of N same-subject
-- list decisions into one (spec: list-aggregation-design, Closure B).
--
-- A subject is Append (list-aggregating) iff some rule emits a @VList@ rhs to a
-- path that matches it. The option schema is the authority for option types,
-- but it lives only at generate time; 'Lips.Kernel.OptionType.checkEmits'
-- (schema-based) already guarantees a rule's rhs value-shape matches its
-- option type, so the value-shape faithfully reflects the schema at run time
-- and run stays nixpkgs-free. No per-problem kernel branch.
--
-- Assembly concatenates the top-strength contributors' @VList@ elements in
-- source-line order (human by (file,line) before derived by parent line),
-- yielding one synthetic decision whose provenance links every contributor so
-- the chain stays walkable to the metal. Replace-across-strengths is the
-- caller's job (it passes only the top-strength contributors).
module Lips.Kernel.Engine.Aggregate
  ( MergeMode (..)
  , mergeModeOf
  , assembleSubject
  ) where

import           Data.List       (sortOn)
import           Data.Maybe      (isJust)
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Kernel.Base              (Base, toList)
import Lips.Kernel.Capture           (matchSubject)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Data       (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Value      (Value (..), parseValue, renderValue)

data MergeMode = Replace | Append
  deriving (Eq, Show)

-- | A subject is Append iff some rule emits a VList rhs to a path pattern that
-- matches it (capture-aware). Else Replace (today's behavior).
mergeModeOf :: [MapRule] -> Subject -> MergeMode
mergeModeOf rules (Subject segs)
  | any emitsListHere rules = Append
  | otherwise               = Replace
  where
    emitsListHere r = any emitMatches (mrEmits r)
    emitMatches e = isListRhs (emRhs e) && isJust (matchSubject (emPath e) segs)
    isListRhs (VList _) = True
    isListRhs _         = False

-- | Assemble one Append subject's top-strength contributors into a single
-- synthetic decision. Each contributor's assertion must be a canonical VList
-- (round-trippable via 'parseValue'/'renderValue'); elements are concatenated
-- in source-line order. A non-VList contributor is a loud 'Left'.
assembleSubject :: [Decision] -> Either Text Decision
assembleSubject [] = Left "assembleSubject: no contributors"
assembleSubject contributors = do
  let ordered  = sortOn sourceKey contributors
  vals <- traverse listValOf ordered
  let assembled = VList (concatMap (\(VList vs) -> vs) vals)
      smallest  = head ordered   -- sortOn is stable; first after sort, but use min id for a stable synthetic id
      synthId   = unId (dId smallest) <> "/append"
  Right Decision
    { dId        = DecisionId synthId
    , dSubject   = dSubject smallest
    , dKind      = Meta
    , dAssertion = Assertion (renderValue assembled)
    , dStrength  = dStrength smallest
    -- Provenance links every contributor (walkable). RuleId "append" is a
    -- synthetic sentinel; there is no real rule, but the type is closed.
    , dProv      = Derived (map dId ordered) (RuleId "append")
    , dRationale = Nothing
    }
  where
    unId (DecisionId i) = i
    listValOf d = case parseValue (unAssertion (dAssertion d)) of
      Right v@(VList _) -> Right v
      Right _           -> Left ("list subject " <> joinSubj (dSubject d)
                                   <> " got a non-list assertion: " <> unAssertion (dAssertion d))
      Left e            -> Left ("list subject " <> joinSubj (dSubject d) <> ": " <> e)
    joinSubj (Subject ss) = T.intercalate "." ss

-- | Assembly order: human (FromSource) before derived (Derived), each by their
-- ultimate source line; ties broken by id. Position is NEVER a merge key --
-- only the assembly rule for Append subjects (spec: ordered assembly).
sourceKey :: Decision -> (Int, Int, Text)
sourceKey d = case dProv d of
  FromSource (SourceLoc _ n) -> (0, n, unId (dId d))
  Derived (DecisionId parent : _) _ -> (1, parentLine parent, unId (dId d))
  _                          -> (2, 0, unId (dId d))
  where
    unId (DecisionId i) = i
    -- The standard id scheme is d<n> (or d<n>.k); the parent's line is n.
    parentLine p = case T.stripPrefix "d" p of
      Just rest -> case TR.decimal (T.takeWhile isDigitRest rest) of
        Right (n, _) -> n
        Left _       -> 0
      Nothing  -> 0
    isDigitRest c = c >= '0' && c <= '9'
```

NOTE: `sourceKey` parses the parent id heuristically (`d<n>`). This covers the standard scheme where a rule-produced Meta decision is `Derived [d<n>] rule`. Document the assumption in the comment (already done).

- [ ] **Step 3: Run tests; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: the aggregation tests PASS. `-Wall` clean.

- [ ] **Step 4: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Aggregate.hs kernel/test/Spec.hs
git commit -m "aggregate: MergeMode, mode derivation, list assembly"
```

---

### Task 3: resolve becomes Append-aware (dependency injection)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Base.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `data ResolveErr = REConflict Conflict | REAssemble Subject Text`; `resolve :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision) -> Base -> Either [ResolveErr] (Map Subject Decision)`; `resolveReplace :: Base -> Either [Conflict] (Map Subject Decision)` (today's behavior, for tests/callers that do not aggregate).
- Consumes: `MergeMode`, `assembleSubject` from Task 2 (passed in, so `Base` imports neither — no cycle).

- [ ] **Step 1: Write the failing test**

In `kernel/test/Spec.hs`, add to the aggregation describe block:

```haskell
    it "resolve: two Append contributors aggregate, not conflict" $ do
      let base = fromList [d1,d2]
          modeOf _ = Append
      case resolve modeOf assembleSubject base of
        Right m -> Map.size m `shouldBe` 1
        Left _  -> expectationFailure "Append contributors must not conflict"
    it "resolve: a Replace subject still conflicts on equal-strength dissent" $ do
      let base = fromList [ (mk "a" "x" "[ \"x\" ]" Stated) { dSubject = pkgs }
                          , (mk "b" "x" "true" Law) { dSubject = pkgs } ]
          modeOf _ = Append
      case resolve modeOf assembleSubject base of
        Left [REAssemble _ _] -> pure ()   -- Law replaces; but its assertion "true" is not a VList -> loud
        Left _                -> pure ()   -- any typed failure acceptable; must NOT silently pick
        Right _               -> expectationFailure "a non-list top-strength decision must not silently win"
    it "resolve: replace-across-strengths -- Law list replaces the Stated list" $ do
      let stated = (mk "s" "x" "[ \"a\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
          law    = (mk "l" "x" "[ \"b\" ]" Law) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
      case resolve (const Append) assembleSubject (fromList [stated,law]) of
        Right m -> winnerAssertion pkgs m `shouldBe` Just (Assertion "[ \"b\" ]")
        Left e  -> expectationFailure ("expected the Law list to replace, got " <> show e)
    it "resolveReplace is today's behavior (no config)" $
      case resolveReplace (fromList [d1,d2]) of
        Left [_] -> pure ()   -- two equal-strength different assertions -> Conflict (today)
        _        -> expectationFailure "without Append, two list lines conflict"
```

Add imports: `import Lips.Kernel.Engine.Aggregate (MergeMode (..), mergeModeOf, assembleSubject)` (already added in Task 2) and ensure `resolve`, `resolveReplace`, `ResolveErr (..)` are exported from `Base`.

Run; expect compile failure (new `resolve` signature).

- [ ] **Step 2: Rewrite `resolve` in `Base.hs`**

```haskell
module Lips.Kernel.Base
  ( Base, empty, fromList, toList, insert, union
  , Conflict (..), ResolveErr (..), resolve, resolveReplace
  ) where

-- | Why a subject could not be resolved: an equal-strength disagreement
-- (Replace), or a list that could not be assembled (Append -- a contributor
-- was not a VList). Both carry the subject so the report is never silent.
data ResolveErr
  = REConflict Conflict
  | REAssemble Subject Text
  deriving (Eq, Show)

-- | Resolve with merge modes. Replace subjects use today's strength logic;
-- Append subjects assemble their top-strength contributors (injection: the
-- caller provides assemble, so Base needs no Value dependency and no cycle).
resolve :: (Subject -> MergeModeLike) -> ([Decision] -> Either Text Decision) -> Base -> Either [ResolveErr] (Map Subject Decision)
resolve modeOf assemble base =
  let bySubject = groupBySubject (toList base)
      results   = map (resolveGroup modeOf assemble) (Map.toList bySubject)
      errs      = concat [es | Left es <- results]
      winners   = [(s, d) | Right (s, d) <- results]
   in if null errs then Right (Map.fromList winners) else Left errs
  where
    -- A local, opacity-broken alias to avoid importing Aggregate (no cycle).
    -- The mode is a plain Bool here: True = Append. The public 'resolve'
    -- below takes MergeMode; this worker takes Bool to stay Base-internal.
    ...

-- To keep Base free of the Aggregate import, expose resolve taking a
-- (Subject -> MergeMode) requires the MergeMode type. Instead, expose a
-- Bool-keyed internal resolve and a public wrapper. See Step 2b.
```

Because `Base` must not import `Aggregate` (cycle: Aggregate imports Base), expose the mode as a `Bool` internally and let the public `resolve` take `(Subject -> MergeMode)` by converting. **Cleaner: define `MergeMode` in `Base`** (it is substrate-level merge vocabulary, not engine-specific), and have `Aggregate` re-export it. Move `data MergeMode = Replace | Append` from `Aggregate` to `Base`. Then `Base.resolve :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision) -> Base -> Either [ResolveErr] (Map Subject Decision)` with no cycle (Base defines MergeMode; Aggregate imports it from Base). Update Aggregate to import `MergeMode` from Base and re-export.

**Step 2b — final `Base.hs` `resolve`:**

```haskell
data MergeMode = Replace | Append
  deriving (Eq, Show)

resolve :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision) -> Base
        -> Either [ResolveErr] (Map Subject Decision)
resolve modeOf assemble base =
  let bySubject = groupBySubject (toList base)
      results   = map (resolveGroup modeOf assemble) (Map.toList bySubject)
      errs      = concat [es | Left es <- results]
      winners   = [(s, d) | Right (s, d) <- results]
   in if null errs then Right (Map.fromList winners) else Left errs

resolveGroup :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
             -> (Subject, [Decision]) -> Either [ResolveErr] (Subject, Decision)
resolveGroup modeOf assemble (subj, ds) =
  case modeOf subj of
    Replace -> case replaceGroup subj ds of
      Left cs        -> Left (map REConflict cs)
      Right (s, d)   -> Right (s, d)
    Append -> case [ d | d <- sortOn dId ds, dStrength d == top ] of
      []     -> error "resolveGroup: empty subject group"  -- impossible
      [one]  -> Right (subj, one)
      tops   -> case assemble tops of
        Right synth -> Right (subj, synth)
        Left e      -> Left [REAssemble subj e]
  where top = maximum (map dStrength ds)

-- | Today's replace-by-strength logic, factored out.
replaceGroup :: Subject -> [Decision] -> Either [Conflict] (Subject, Decision)
replaceGroup subj ds =
  case sortOn dId (filter ((== top) . dStrength) ds) of
    (chosen : rest) ->
      let dissent = filter ((/= dAssertion chosen) . dAssertion) rest
       in case dissent of
            [] -> Right (subj, chosen)
            _  -> Left [Conflict subj chosen d | d <- dissent]
    [] -> error "replaceGroup: empty"
  where top = maximum (map dStrength ds)

-- | Today's behavior: all Replace, no assembly. For tests and callers that do
-- not aggregate.
resolveReplace :: Base -> Either [Conflict] (Map Subject Decision)
resolveReplace base =
  case resolve (const Replace) (\_ -> Left "assemble unused") base of
    Left errs -> Left [ c | REConflict c <- errs ]
    Right m   -> Right m
```

Remove the old `resolve` and `resolveGroup`. Keep `Conflict`, `groupBySubject`, `union`, etc.

- [ ] **Step 3: Update `Aggregate` to import `MergeMode` from `Base`**

In `kernel/src/Lips/Kernel/Engine/Aggregate.hs`, delete the `data MergeMode` definition and import it:

```haskell
import Lips.Kernel.Base (Base, toList, MergeMode (..))
```
Re-export `MergeMode (..)` from Aggregate so existing imports still work.

- [ ] **Step 4: Update existing resolve tests to use `resolveReplace`**

The existing `"merge"`, `"agreement"`, `"conflict"`, `"resolve is deterministic"` tests (lines ~95-143) call `resolve base`. Change each to `resolveReplace base`. The QuickCheck confluence test (`resolve (fromList perm) === resolve (fromList pool)`) becomes `resolveReplace (fromList perm) === resolveReplace (fromList pool)`. The "merge algebra" property test (~1167) likewise.

- [ ] **Step 5: Run the suite; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS. Existing resolve tests (via `resolveReplace`) unchanged in behavior; new Append tests pass.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Kernel/Base.hs kernel/src/Lips/Kernel/Engine/Aggregate.hs kernel/test/Spec.hs
git commit -m "resolve: Append-aware merge mode (dependency-injected assembly)"
```

---

### Task 4: Thread the merge config through Run, Realize, and the CLI

**Files:**
- Modify: `kernel/src/Lips/Kernel/Realize.hs`
- Modify: `kernel/src/Lips/Kernel/Run.hs`
- Modify: `kernel/app/Main.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `realize :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision) -> Base -> Either RealizeError Text`; `run`/`runBase` take the same two args; `RunError` gains no new variant (assembly failure maps to `Unrealizable`).

- [ ] **Step 1: Write the failing end-to-end test**

In `kernel/test/Spec.hs`, add to the aggregation block:

```haskell
    it "end-to-end: two install lines aggregate into one systemPackages list" $ do
      let pat = patOne "p" [TLit "install", THole "pkg"] Fact Stated
                  [SHole "pkg"] [SHole "value"]
          rule = MapRule "r" Fact ["pkg"]
                   [ Emit ["environment","systemPackages"] (VList [VStr [PHole "value"]]) ]
          prog = T.unlines [ "install htop.", "install ripgrep." ]
          modeOf = mergeModeOf [rule]
      case crystallize "f" [pat] prog of
        Right base -> case runBase 100 (map toRule [rule]) [] modeOf assembleSubject base of
          Right mod_ -> mod_ `shouldSatisfy` T.isInfixOf "environment.systemPackages = [ \"htop\" \"ripgrep\" ];"
          Left e     -> expectationFailure ("run failed: " <> show e)
        Left e -> expectationFailure ("crystallize failed: " <> show e)
```

(`crystallize` and `runBase` are already imported.) Run; expect compile failure (`runBase` arity changed).

- [ ] **Step 2: Update `realize`**

In `kernel/src/Lips/Kernel/Realize.hs`:

```haskell
realize :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision) -> Base
        -> Either RealizeError Text
realize modeOf assemble base = do
  winners <- either (Left . map toRealizeErr) Right (resolve modeOf assemble base)
  renderModule (Map.toList winners)
  where
    toRealizeErr (REConflict c) = RConflicts [c]
    toRealizeErr (REAssemble s e) = RMalformed s e
```

Import `MergeMode`, `ResolveErr(..)`, `resolve` from `Base`. The `RConflicts` case now wraps a single conflict (from REConflict) — keep the list form if preferred, but REConflict carries one; adjust `RConflicts [Conflict]` to take a singleton list, or change `RConflicts` to a single `Conflict`. To minimize churn, keep `RConflicts [Conflict]` and emit `[c]`.

- [ ] **Step 3: Update `Run.hs`**

```haskell
run :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
    -> Int -> [Rule] -> [Demand] -> Text -> Either RunError Text
run modeOf assemble budget rules demands src = do
  base0 <- first ParseRejected (readBase src)
  runBase modeOf assemble budget rules demands base0

runBase :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
        -> Int -> [Rule] -> [Demand] -> Base -> Either RunError Text
runBase modeOf assemble budget rules demands base0 = do
  winners <- first (Conflicted . concatMap confOf) (resolve modeOf assemble base0)
  let base1 = fromList (Map.elems winners)
  case map demQuestion (openQuestions demands base1) of
    []        -> Right ()
    questions -> Left (OpenQuestions questions)
  ground <- first RefineFailed (refine budget rules base1)
  let realizable = filter ((/= Concept) . dKind) (toList ground)
  case filter ((/= Meta) . dKind) realizable of
    []      -> case realize modeOf assemble (fromList realizable) of
                 Right nixMod              -> Right nixMod
                 Left (RConflicts cs)      -> Left (Conflicted cs)
                 Left (RDangling ns)       -> Left (Unrealizable ["references artifact(s) nothing builds: " <> T.intercalate ", " ns])
                 Left (RBadArtifact n why) -> Left (Unrealizable ["artifact " <> n <> ": " <> why])
                 Left (RMalformed s e)     -> Left (Unrealizable ["option " <> subjText s <> ": " <> e])
    leftovers -> Left (Unmapped leftovers)
  where
    confOf (REConflict c)   = [c]
    confOf (REAssemble _ _) = []   -- assembly failure on the human base is rare; if it occurs it surfaces at realize as RMalformed
    subjText (Subject ss) = T.intercalate "." ss
```

Import `MergeMode`, `ResolveErr(..)`, `resolve` from `Base`, and `RMalformed(..)`/`RealizeError(..)` from `Realize`.

- [ ] **Step 4: Update the CLI (`validate`)**

In `kernel/app/Main.hs`, `validate`:

```haskell
validate :: FilePath -> EngineData -> Text -> Either Failure (Base, Text)
validate file eng program =
  case crystallize file (edPatterns eng) program of
    Left errs  -> Left (FailRead errs)
    Right base -> do
      let rules = map (toRule . bindSelf (instanceName file)) (edRules eng)
          modeOf = mergeModeOf (edRules eng)   -- derived from rule emits; schema authority upheld by checkEmits at generate
      case runBase modeOf assembleSubject budget (map toDemand (edDemands eng)) rules base of
        Left err        -> Left (FailRun err)
        Right nixModule -> Right (base, nixModule)
```

Import `mergeModeOf`, `assembleSubject` from `Lips.Kernel.Engine.Aggregate`. Note `mergeModeOf` takes the UN-bound rules; since `<self>` binding does not change which emits are VLists, `edRules eng` (pre-bind) is fine. (If a rule emits `<self>` in a VList path, `<self>` is a literal segment for matching purposes — `matchSubject` treats it as a literal, which is correct pre-bind only if the concrete subject also has `<self>`; but concrete Meta subjects have `<self>` already replaced. So pass the BOUND rules to `mergeModeOf` for correctness: `let boundRules = map (bindSelf (instanceName file)) (edRules eng); modeOf = mergeModeOf boundRules`.)

- [ ] **Step 5: Update existing run/realize test call sites**

Search `test/Spec.hs` for `realize ` and `runBase ` and `run ` calls:
- The realization tests (~242-330) call `realize (fromList ...)`. These test realize on hand-constructed ground bases with NO aggregation needed. Change to `realize (const Replace) (\_ -> Left "unused") (fromList ...)`. (Or add a `realizeReplace :: Base -> Either RealizeError Text = realize (const Replace) ...` helper in Realize and use it.)
- Add `realizeReplace` to `Realize.hs` for test convenience:

```haskell
realizeReplace :: Base -> Either RealizeError Text
realizeReplace = realize (const Replace) (\_ -> Left "assemble unused")
```

Use `realizeReplace` in all existing realization tests (no behavior change).
- The run-pipeline tests (~335-384) and feed corpus / edit-tolerance tests call `run`/`runBase`. Update them to pass `(const Replace)` and `(\_ -> Left "unused")`, OR add `runReplace`/`runBaseReplace` helpers. Add helpers in `Run.hs`:

```haskell
runBaseReplace :: Int -> [Rule] -> [Demand] -> Base -> Either RunError Text
runBaseReplace = runBase (const Replace) (\_ -> Left "assemble unused")
```

and use it in tests that don't exercise aggregation. (The feed corpus / edit-tolerance tests use a shared `runLoose` helper — update that one helper.)

- [ ] **Step 6: Run the suite; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS, including the new end-to-end aggregation test.

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Kernel/Realize.hs kernel/src/Lips/Kernel/Run.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "run/realize: thread merge config; B aggregates end-to-end"
```

---

### Task 5: B conformance — ordered, record-valued, and attrsOf-of-list

**Files:**
- Modify: `kernel/test/Spec.hs`

**Interfaces:** none new; pins the spec's completeness cases.

- [ ] **Step 1: Write the conformance tests**

Add to the aggregation block:

```haskell
    it "ordered: contributors assemble in source-line order (ExecStartPre)" $ do
      let first  = (mk "a" "x" "[ \"setup-a\" ]" Stated) { dSubject = Subject ["s","x","ExecStartPre"], dProv = FromSource (SourceLoc "f" 5) }
          second = (mk "b" "x" "[ \"setup-b\" ]" Stated) { dSubject = Subject ["s","x","ExecStartPre"], dProv = FromSource (SourceLoc "f" 2) }
      case assembleSubject [first,second] of
        Right synth -> dAssertion synth `shouldBe` Assertion "[ \"setup-b\" \"setup-a\" ]"
        Left e      -> expectationFailure (show e)
    it "record-valued: listOf-submodule elements aggregate (ensureUsers)" $ do
      let u1 = (mk "a" "x" "[ { name = \"app\"; ensureDBOwnership = true; } ]" Stated) { dSubject = Subject ["services","postgresql","ensureUsers"], dProv = FromSource (SourceLoc "f" 1) }
          u2 = (mk "b" "x" "[ { name = \"web\"; ensureDBOwnership = true; } ]" Stated) { dSubject = Subject ["services","postgresql","ensureUsers"], dProv = FromSource (SourceLoc "f" 2) }
      case assembleSubject [u1,u2] of
        Right synth -> dAssertion synth `shouldBe`
          Assertion "[ { name = \"app\"; ensureDBOwnership = true; } { name = \"web\"; ensureDBOwnership = true; } ]"
        Left e      -> expectationFailure (show e)
    it "attrsOf-of-list (Q5): a capture-bearing list emit aggregates per concrete key" $ do
      let r = MapRule "r" Fact ["grp"]
                [ Emit ["g","<name>","items"] (VList [VStr [PHole "value"]]) ]
          modeOf = mergeModeOf [r]
      modeOf (Subject ["g","key1","items"]) `shouldBe` Append
      modeOf (Subject ["g","key2","items"]) `shouldBe` Append
      -- two contributors on the SAME concrete key aggregate; different keys coexist
      let k1a = (mk "a" "x" "[ \"x\" ]" Stated) { dSubject = Subject ["g","key1","items"], dProv = FromSource (SourceLoc "f" 1) }
          k1b = (mk "b" "x" "[ \"y\" ]" Stated) { dSubject = Subject ["g","key1","items"], dProv = FromSource (SourceLoc "f" 2) }
          k2  = (mk "c" "x" "[ \"z\" ]" Stated) { dSubject = Subject ["g","key2","items"], dProv = FromSource (SourceLoc "f" 3) }
      case resolve modeOf assembleSubject (fromList [k1a,k1b,k2]) of
        Right m -> Map.size m `shouldBe` 2   -- key1 (assembled) + key2
        Left e  -> expectationFailure (show e)
    it "replace-across-strengths: a Law list replaces a Stated list, not appends" $ do
      let st = (mk "s" "x" "[ \"a\" ]" Stated) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 1) }
          lw = (mk "l" "x" "[ \"b\" ]" Law) { dSubject = pkgs, dProv = FromSource (SourceLoc "f" 2) }
      case resolve (const Append) assembleSubject (fromList [st,lw]) of
        Right m -> winnerAssertion pkgs m `shouldBe` Just (Assertion "[ \"b\" ]")
        Left e  -> expectationFailure (show e)
```

- [ ] **Step 2: Run; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add kernel/test/Spec.hs
git commit -m "conformance: ordered, record-valued, attrsOf-of-list aggregation"
```

---

### Task 6: C — template tail hole (bind the rest of a line's tokens)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Pattern.hs`
- Modify: `kernel/src/Lips/Kernel/Lang/Store.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:** `TplTok` gains `TTail Text`; `matchTemplate` allows a trailing `TTail` to consume all remaining tokens (≥1).

- [ ] **Step 1: Write the failing test**

Add a describe block:

```haskell
  describe "template tail hole (C: many items on one line)" $ do
    it "a trailing <name.tail> binds the rest of the tokens" $ do
      let p = patOne "p" [TLit "install", TTail "pkgs"] Fact Stated [SHole "pkgs"] [SHole "value"]
          toks = tokenizeLine "install htop, ripgrep, tmux."
      matchTemplate (pTemplate p) toks `shouldSatisfy` isJust
    it "a tail hole matching zero tokens fails (deduce-or-fail, never guess)" $ do
      let p = patOne "p" [TLit "install", TTail "pkgs"] Fact Stated [SHole "pkgs"] [SHole "value"]
      matchTemplate (pTemplate p) (tokenizeLine "install") `shouldSatisfy` isNothing
    it "a tail hole must be the last template token" $
      parsePatternBody "p" "install <pkgs.tail> on <host> => fact pkg stated \"<value>\"" `shouldSatisfy` isLeft
```

Add `TTail` to the `TplTok` import if needed. Run; expect compile failure (`TTail` absent).

- [ ] **Step 2: Add `TTail` and tail matching**

In `kernel/src/Lips/Kernel/Lang/Pattern.hs`:

```haskell
data TplTok = TLit Text | THole Text | TTail Text
  deriving (Eq, Show)
```

Update `matchTemplate` to handle a trailing `TTail`:

```haskell
matchTemplate :: [TplTok] -> [(Text, Text)] -> Maybe (Map Text Text)
matchTemplate toks line = go toks line Map.empty
  where
    go [] [] binds                          = Just binds
    go [] _  _                              = Nothing
    go (TTail name : []) rest binds
      | null rest                           = Nothing        -- Q4: empty tail fails
      | otherwise                           = Just (Map.insert name (T.unwords (map fst rest)) binds)
    go (TTail _ : _ : _) _ _                = Nothing        -- a tail must be last (validated on read; defense in depth)
    go (TLit lit : ts) ((_, norm) : rs) binds
      | lit == norm = go ts rs binds
      | otherwise   = Nothing
    go (THole h : ts) ((surface, _) : rs) binds =
      case Map.lookup h binds of
        Nothing               -> go ts rs (Map.insert h surface binds)
        Just prev | prev == surface -> go ts rs binds
                  | otherwise       -> Nothing
    go (THole _ : _) [] _                   = Nothing
```

(The old `matchTemplate` required equal length and folded; this rewrite preserves single-token-hole semantics and adds the tail case. Re-verify the existing pattern-matching tests still pass.)

- [ ] **Step 3: Render and parse `TTail` in `Store.hs`**

In `kernel/src/Lips/Kernel/Lang/Store.hs`:

`renderTplTok`:
```haskell
renderTplTok (TLit t)   = t
renderTplTok (THole h)  = "<" <> h <> ">"
renderTplTok (TTail h)  = "<" <> h <> ".tail>"
```

`parseTplTok` — a token ending in `.tail>` inside `<...>` becomes `TTail`:
```haskell
parseTplTok w
  | Just inner <- unquote w = maybe (TLit (T.toLower inner)) THole (holeName inner)
  | Just h <- holeName (stripTrailingPunct w) =
      case T.stripSuffix ".tail" h of
        Just name -> TTail name
        Nothing   -> THole h
  | otherwise = TLit (normalizeToken w)
```

`parseBody` — add a validation that a `TTail` may appear only as the LAST template token:
```haskell
  -- after building `template`, reject a TTail that is not last
  let tailNotLast = any isTail (init template)
      isTail (TTail _) = True
      isTail _         = False
  if tailNotLast then Left ("pattern " <> pid <> ": a <name.tail> hole must be the last token")
                 else Right p   -- (fold into the existing final check)
```
Also ensure `holesOf` includes tail names so target holes bound by a tail are accepted: `holesOf p = [h | tok <- pTemplate p, h <- tokHole tok]` where `tokHole (THole h) = [h]; tokHole (TTail h) = [h]; tokHole _ = []`.

- [ ] **Step 4: Run; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS (existing pattern tests unchanged; new tail tests pass).

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Lang/Pattern.hs kernel/src/Lips/Kernel/Lang/Store.hs kernel/test/Spec.hs
git commit -m "pattern: template tail hole binds the rest of a line's tokens"
```

---

### Task 7: C — value tail hole (rhs becomes a VList of the program value's tokens)

**Files:**
- Modify: `kernel/src/Lips/Kernel/Engine/Value.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:** `Value` gains `VTail Text` (a rhs hole `<value.tail>` that fills to a `VList` of the program value's whitespace tokens, each trailing-punct-stripped). `parseValue`/`renderValue`/`renderRealized`/`fillValue`/`valueArtifactNames` cover it.

- [ ] **Step 1: Write the failing test**

Add to the value-language describe block:

```haskell
    it "a <value.tail> rhs parses and renders canonically" $ do
      parseValue "<value.tail>" `shouldBe` Right (VTail "value")
      renderValue (VTail "value") `shouldBe` "<value.tail>"
    it "fillValue on a tail hole splits the program value into a VList of tokens" $
      fillValue (const (Right "htop, ripgrep, tmux.")) (VTail "value")
        `shouldBe` Right "[ \"htop\" \"ripgrep\" \"tmux\" ]"
    it "an empty program value for a tail hole fails loud" $
      fillValue (const (Right "")) (VTail "value") `shouldSatisfy` isLeft
```

Add `VTail` to the `Value` import. Run; expect compile failure.

- [ ] **Step 2: Add `VTail` and its handling**

In `kernel/src/Lips/Kernel/Engine/Value.hs`:

```haskell
data Value
  = VStr [Piece] | VList [Value] | VBool Bool | VInt Integer | VFloat Double
  | VPath Text | VNull | VHole HoleType Text | VRef Ref | VAttr [(Text, Value)]
  | VTail Text   -- ^ @<value.tail>@: fills to a VList of the program value's
                 -- whitespace tokens (trailing sentence punctuation stripped).
                 -- The whole rhs, not a list element: the line's many items
                 -- become one list, which Append (B) can aggregate with others.
  deriving (Eq, Show)
```

`pTypedHole` — recognize `value.tail`:
```haskell
pTypedHole more =
  let (inside, after) = T.breakOn ">" more
   in if T.null after
        then Left ("unterminated hole <" <> inside)
        else case inside of
          "value.tail" -> Right (VTail "value", T.drop 1 after)
          _ -> case T.splitOn ":" inside of
            [hn, ty] | validHoleName hn, Just ht <- parseHoleType ty ->
                Right (VHole ht hn, T.drop 1 after)
            _ -> Left ("a hole outside a string must be typed "
                   <> "<value:int|bool|float|path> or <value.tail> (or <value.N:...>): <" <> inside <> ">")
```

`renderValue (VTail _) = "<value.tail>"`. `renderRealized (VTail _) = "<value.tail>"` (never reaches a realized module unfilled — fillValue replaces it; if it slips through, fail loud at realize's parse: `<value.tail>` is not a value the module can carry, so a `RMalformed` results. Acceptable: an unfilled tail is a mint defect.)

`fillValue` — handle `VTail`:
```haskell
    fillV (VTail h) = do
      tok <- pick h
      let toks = map stripTrailingPunct (filter (not . T.null) (T.words tok))
      if null toks
        then Left ("value hole <" <> h <> ".tail> matched no tokens (empty tail)")
        else Right (VList (map (VStr . (: []) . PLit) toks))
```
(`stripTrailingPunct` is in `Pattern.hs`; to avoid a Value→Pattern dependency, duplicate the one-liner locally or move `stripTrailingPunct` to a tiny shared util. Prefer duplicating the one-liner in Value.hs to keep modules decoupled, with a comment naming the twin.)

`valueArtifactNames (VTail _) = []` (a tail produces string elements, never refs).

- [ ] **Step 3: End-to-end C test**

Add to the aggregation block:

```haskell
    it "end-to-end C: one line with many packages -> one VList, aggregatable with B" $ do
      let pat = patOne "p" [TLit "install", TTail "pkgs"] Fact Stated [SHole "pkgs"] [SHole "value"]
          rule = MapRule "r" Fact ["pkgs"] [ Emit ["environment","systemPackages"] (VTail "value") ]
          prog = T.unlines [ "install htop, ripgrep.", "install tmux." ]
          modeOf = mergeModeOf [rule]
      case crystallize "f" [pat] prog of
        Right base -> case runBase modeOf assembleSubject 100 (map toRule [rule]) [] base of
          Right mod_ -> mod_ `shouldSatisfy` T.isInfixOf "environment.systemPackages = [ \"htop\" \"ripgrep\" \"tmux\" ];"
          Left e     -> expectationFailure ("run failed: " <> show e)
        Left e -> expectationFailure ("crystallize failed: " <> show e)
```

- [ ] **Step 4: Run; confirm green**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Engine/Value.hs kernel/test/Spec.hs
git commit -m "value: <value.tail> rhs -> VList of program tokens (C)"
```

---

### Task 8: Update the milestone ledger and TODO

**Files:**
- Modify: `DESIGN.md` (section 13)
- Modify: `TODO.md`

- [ ] **Step 1: Move the two Missing items to Done in DESIGN.md §13**

In `DESIGN.md`, remove from "Missing":
- "List aggregation across decisions (N lines -> one list-valued option)."
- "Multi-token tail holes."

Add to "Done" a new entry (mirroring the style of existing Done entries):

```markdown
- **List aggregation (B + C, no block construct).** N sibling lines fold into
  one list-valued option, and one line may carry many items, with no block
  construct, no dictated collection syntax, and no new ordering key on the
  decision. (B) An `Append` merge mode alongside `Replace`, derived from the
  rule emits (a subject whose rule emits a `VList` rhs appends; the option
  schema is the authority but lives only at generate, and `checkEmits` already
  guarantees the rhs value-shape matches the option type, so run stays
  nixpkgs-free). `Append` assembles the top-strength contributors' `VList`
  elements in source-line order (human by `(file,line)` before derived by
  parent line) into one synthetic decision whose provenance links every
  contributor; replace-across-strengths holds (a stronger list replaces the
  whole list; `Append` is only same-strength aggregation). Cross-module list
  composition stays NixOS's job. (C) A template tail hole `<name.tail>` binds
  the rest of a line's tokens, and a value tail hole `<value.tail>` makes a rhs
  that fills to a `VList` of the program value's tokens (trailing punctuation
  stripped); an empty tail fails loud. A multiline collection is N flat lines
  whose patterns share a list subject; a header, if wanted, is an optional
  `Concept`. Prerequisite refactor (R1): Meta assertions are stored canonically
  (`renderValue`, round-trippable) and `realize` is the single canonical→Nix
  render point, which also completed the round-trip and replaced a quote-aware
  text artifact-ref scanner with Value-based detection. Domain-blind preserved
  (invariant 1); the canonical stored form stays one-decision-per-line. Design:
  `docs/superpowers/specs/2026-07-24-list-aggregation-design.md`.
```

- [ ] **Step 2: Update TODO.md**

Replace the "List aggregation" section's open questions and build order with a resolved note, or delete the section and add a one-line "Done" pointer. Concretely, replace the whole "## List aggregation" block with:

```markdown
## List aggregation — DONE (2026-07-24)

B (Append merge mode) + C (tail holes) landed; see DESIGN.md §13.
All open questions resolved (replace-across-strengths; human-before-derived
ordering; `<value.tail>` spelling; empty tail = error; attrsOf-of-list via
wildcard). No block construct (D collapsed).
```

- [ ] **Step 3: Commit**

```bash
git add DESIGN.md TODO.md
git commit -m "ledger: list aggregation (B+C) done"
```

---

## Self-Review

**1. Spec coverage.** Spec Closure B (Append merge mode, schema-derived → rule-emit-derived, replace-across-strengths, assembly by source-line, `.expect`/`@gen` preserved): Tasks 2-4. Spec Closure C (tail hole `<value.tail>`, empty fails loud): Tasks 6-7. Spec "D collapsed / no block construct / no header required": honored — no task adds a block; Task 5 pins the N-flat-lines + optional Concept composition. Spec R1 prerequisite (canonical assertions, realize renders, round-trip, Value-based artifact detection): Task 1. Spec Q1-Q5: Q1 Task 3+5, Q2 Task 2 (`sourceKey`), Q3/Q4 Task 6-7, Q5 Task 5. Spec invariants 1-6: invariant 1 (no model at run) — all tasks deterministic; invariant 2 (fail loud) — `RMalformed`/`REAssemble`/empty-tail `Left`; invariant 3 (closed grammar) — `VTail`/`TTail` extend the closed grammars; invariant 4 (workarounds→kernel) — B+C are kernel physics; invariant 5 (`.expect` gates) — unchanged, module output identical so contracts hold; invariant 6 (`@gen`) — untouched (engine data only; merge mode is derived, not stored, so no new `@gen`-stamped section).

**2. Placeholder scan.** The `assignment` refactor in Task 1 has two sketched forms — the implementer must pick the `(Subject, Decision, Value)` threading (the second, cleaner form) and drop the re-parse. Made explicit in the NOTE. Task 4's `mergeModeOf` bound-vs-unbound rules: resolved (use bound rules). No TBD/TODO elsewhere.

**3. Type consistency.** `MergeMode` defined once (in `Base`, re-exported by `Aggregate`) — consistent across Tasks 2-4. `resolve`/`realize`/`runBase` signatures match across Tasks 3-4. `assembleSubject :: [Decision] -> Either Text Decision` consistent (Tasks 2-5). `VTail Text` / `TTail Text` consistent (Tasks 6-7). `ResolveErr (REConflict|REAssemble)` and `RealizeError`'s `RMalformed` consistent across Tasks 1-4.
