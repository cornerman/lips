# The Meaning Dimension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give lips a gate that observes a running thing (claims) and a gate that keeps baked source causally tied to the program lines it was minted from (source-line provenance).

**Architecture:** Two mechanisms, three milestones. Milestone 1 generalizes the existing `sourceSpecGate` and extracts its judgment into a pure, tested function. Milestone 2 adds a reserved emit head `claim.<id>` to the kernel's build-group vocabulary (the namespace `artifact.<name>` already occupies), projects it to a `claims.nix` rendered beside `artifact.nix`, derives each claim's PLACE (nix-sandbox derivation vs booted `nixosTest`) from whether its command names only artifacts, and gates `generate` on it. Milestone 3 re-mints four engines to exercise both.

**Tech Stack:** Haskell (GHC, no framework; hspec + QuickCheck suite in `kernel/test/Spec.hs`), Nix (rendered output text), Python (the one comparison implementation, shared by both claim places).

**Spec:** `docs/superpowers/specs/2026-07-31-meaning-dimension-design.md`

## Global Constraints

- The kernel is domain-blind: no `if language ==`, no builtin list of builders,
  no domain keyword. `claim` is a closed grammar head the engine fills.
- `compile` and `check` never call a model. No AI after generate, ever.
- Deduce-or-fail: unreadable or unrunnable input fails loud naming the remedy.
  A claim that cannot run is a LOUD failure, never a skip.
- Illegal states unrepresentable: claim values stay in the closed value grammar
  (`Kernel/Engine/Value.hs`); computation has no constructor.
- Generated output is never hand-edited.
- The suite and app must stay `-Wall` clean.
- Comparison of claim stdout is EXACT (byte-equal), with exactly ONE trailing
  newline stripped from the observed bytes. Containment stays banned.
- Fast test loop, run from the repo root:
  `nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'`
  (equivalently `just test`). Nix flakes see only git-tracked files: `git add`
  before any `nix build`/`nix run`.
- Work in a worktree under `.worktrees/`, single-line commits, rebase +
  ff-merge to main. Update `DESIGN.md` §13 and `TODO.md` when a milestone lands.
- Known, accepted deviation to record in DESIGN when Milestone 2 lands: for a
  claim-bearing program `lips check` builds `#claims`, so it needs ambient
  nixpkgs. `check` stays nixpkgs-free for every claim-free program (unchanged).

---

## Milestone 1 — Source-Line Provenance

### Task 1: Pure source-spec verdict, with the unrecorded-program escape closed

**Files:**
- Modify: `kernel/src/Lips/Kernel/Lang/Diagnose.hs` (add `SourceSpecVerdict`, `sourceSpecVerdict`; keep `retiredConcepts` exported, it is used by the new function and by existing tests)
- Modify: `kernel/app/Main.hs:1313-1337` (`sourceSpecGate` becomes an IO shell over the pure function)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Base (Base, toList)`, `Lips.Kernel.Decision (Decision (..), Kind (Concept))`, existing `retiredConcepts :: Base -> Base -> [Decision]`.
- Produces:
  ```haskell
  data SourceSpecVerdict
    = SpecHolds
    | SpecRetired [Decision]
    | SpecUnrecorded [Decision]
    deriving (Eq, Show)

  sourceSpecVerdict :: Maybe Base -> [Base] -> Base -> SourceSpecVerdict
  -- ^ (recorded section for THIS program, if the record holds one)
  --   (every recorded section's base)
  --   (the current program's base)
  ```

- [ ] **Step 1: Write the failing tests**

Add to `kernel/test/Spec.hs`, inside a new `describe` block near the existing
`retiredConcepts` tests:

```haskell
  describe "source-spec verdict (baked source keeps its specification)" $ do
    let concept subj txt = Decision
          { dId = DecisionId subj
          , dSubject = Subject [subj]
          , dKind = Concept
          , dAssertion = Assertion txt
          , dStrength = Stated
          , dProv = FromSource (SourceLoc "p.x.lips" 1)
          , dRationale = Nothing
          }
        fact = (\d -> d { dKind = Fact }) . concept
        b ds = fromList ds

    it "holds when the recorded section is restated verbatim" $
      sourceSpecVerdict (Just (b [concept "io.filter" "keep every field"]))
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.filter" "keep every field"])
        `shouldBe` SpecHolds

    it "reports a deleted recorded concept as retired" $
      sourceSpecVerdict (Just (b [concept "io.filter" "keep every field"]))
                        [b [concept "io.filter" "keep every field"]]
                        (b [fact "cmd.logscan.name" "logscan"])
        `shouldBe` SpecRetired [concept "io.filter" "keep every field"]

    it "reports a reworded concept as retired (text is part of the spec)" $
      sourceSpecVerdict (Just (b [concept "io.filter" "every field equals it"]))
                        [b [concept "io.filter" "every field equals it"]]
                        (b [concept "io.filter" "every field differs from it"])
        `shouldBe` SpecRetired [concept "io.filter" "every field equals it"]

    it "lets an unrecorded sibling restate only recorded concepts" $
      sourceSpecVerdict Nothing
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.filter" "keep every field"])
        `shouldBe` SpecHolds

    it "refuses an unrecorded sibling stating a concept the record never saw" $
      sourceSpecVerdict Nothing
                        [b [concept "io.filter" "keep every field"]]
                        (b [concept "io.sort" "sort the output"])
        `shouldBe` SpecUnrecorded [concept "io.sort" "sort the output"]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `just test`
Expected: FAIL, `Variable not in scope: sourceSpecVerdict`.

- [ ] **Step 3: Implement the pure verdict**

In `kernel/src/Lips/Kernel/Lang/Diagnose.hs`, extend the export list with
`SourceSpecVerdict (..)` and `sourceSpecVerdict`, and append:

```haskell
-- | The verdict on a baked-source language's specification, for ONE program.
data SourceSpecVerdict
  = SpecHolds
  | -- | Mint-time concepts this program no longer states (deleted or reworded).
    SpecRetired [Decision]
  | -- | Concepts this program states that no recorded section ever stated, so
    --   the committed source was never written from them.
    SpecUnrecorded [Decision]
  deriving (Eq, Show)

-- | Judge a program against the corpus its language's source was minted from.
--
-- Two directions, because a language's source is shared by every program in it:
--
--   * the program HAS a recorded section: every concept the mint saw must still
--     be stated ('retiredConcepts'), so a deleted or reworded specification
--     sentence fails loud instead of leaving the baked source orphaned;
--   * the program has NO recorded section (added or renamed after the mint):
--     every concept it states must appear somewhere in the recorded corpus.
--     That keeps sibling reuse free -- a concept pattern is all-literal, so a
--     sibling restating it produces the identical subject and text -- while a
--     sentence the source was never written from is refused rather than
--     silently skipped (the escape this closes).
--
-- Pure: the caller reads the record, crystallizes, and reports.
sourceSpecVerdict :: Maybe Base -> [Base] -> Base -> SourceSpecVerdict
sourceSpecVerdict mrecorded corpus now =
  case mrecorded of
    Just was -> case retiredConcepts was now of
      []      -> SpecHolds
      retired -> SpecRetired retired
    Nothing -> case [ d | d <- concepts now, key d `notElem` corpusKeys ] of
      []      -> SpecHolds
      unknown -> SpecUnrecorded unknown
  where
    concepts b = [ d | d <- toList b, dKind d == Concept ]
    key d      = (dSubject d, dAssertion d)
    corpusKeys = [ key d | sec <- corpus, d <- concepts sec ]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `just test`
Expected: PASS, whole suite green and `-Wall` clean.

- [ ] **Step 5: Wire the gate to the pure verdict**

In `kernel/app/Main.hs`, replace the body of `sourceSpecGate` (currently at
1313-1337) with an IO shell. It needs every recorded section, so it uses
`recordedProgram` for this program and the record's whole corpus for the rest.
Check the record helpers first: `Lips.Generate.Record` exports
`recordedProgram :: FilePath -> Text -> Maybe Text` (the section for one
program) and `corpusText`. If the module has no "every section" accessor, add
one beside `recordedProgram`:

```haskell
-- | Every program section the record holds: @(program file, its text)@. The
-- record stores the corpus verbatim, so this is a read, not a reconstruction.
recordedPrograms :: Text -> [(FilePath, Text)]
```

(implement it by the same section splitting `recordedProgram` already does, and
express `recordedProgram f = lookup f . recordedPrograms`, so one parser serves
both and they cannot drift).

Then:

```haskell
sourceSpecGate :: FilePath -> FilePath -> EngineData -> Text -> IO ()
sourceSpecGate dir file eng program = do
  baked <- doesDirectoryExist (artifactsPathIn dir file)
  when baked $ do
    mrec <- tryRead (generationPathIn dir file)
    case mrec of
      -- A baked tree with no readable record cannot be judged at all, and an
      -- unjudged specification must never pass as judged.
      Nothing  -> die (report
        (T.pack file <> ": the language bakes source, but its generation record"
          <> " is missing or unreadable, so the specification the source was"
          <> " written from cannot be read.")
        [T.pack (generationPathIn dir file)]
        ("\8594 rebuild both from the program as it stands: lips generate " <> T.pack file))
      Just rec -> do
        let cryst t = crystallize file (edPatterns eng) t
            sections = recordedPrograms rec
        -- Every recorded section must still crystallize, or the comparison is
        -- meaningless (the same refusal the old gate made for this program).
        corpus <- forM sections $ \(f, t) -> case cryst t of
          Right b -> pure b
          Left _  -> die (report
            ("the program recorded in " <> T.pack (generationPathIn dir file)
              <> " no longer crystallizes with the committed language.")
            [T.pack f]
            ("\8594 rebuild both from the program as it stands: lips generate " <> T.pack file))
        case cryst program of
          Left _  -> pure ()   -- the caller reports the current program's read errors
          Right now -> case sourceSpecVerdict (lookup file sections >>= either (const Nothing) Just . cryst) corpus now of
            SpecHolds -> pure ()
            SpecRetired retired -> die (report
              (T.pack file <> " dropped " <> plural (length retired) "line"
                <> " that the built source was written from:")
              [ a <> " (" <> niceSubject (dSubject d) <> ")"
              | d <- retired, let Assertion a = dAssertion d ]
              ("\8594 state it again, or rebuild the source for the program as it stands: "
                <> "lips generate " <> T.pack file))
            SpecUnrecorded unknown -> die (report
              (T.pack file <> " states " <> plural (length unknown) "line"
                <> " the built source was never written from:")
              [ a <> " (" <> niceSubject (dSubject d) <> ")"
              | d <- unknown, let Assertion a = dAssertion d ]
              ("\8594 the source is minted from the program, so rebuild it: "
                <> "lips generate " <> T.pack file))
```

Import `sourceSpecVerdict`, `SourceSpecVerdict (..)` from
`Lips.Kernel.Lang.Diagnose` and `recordedPrograms` from `Lips.Generate.Record`.

- [ ] **Step 6: Verify nothing regressed against the committed corpus**

Run: `just test`
Then: `just check-expect`
Expected: both green. Every committed example either has a recorded section
(unchanged path) or states only recorded concepts.

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Kernel/Lang/Diagnose.hs kernel/src/Lips/Generate/Record.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "provenance: judge a baked language's specification purely, and refuse an unrecorded sentence"
```

---

## Milestone 2 — Observable Claims

### Task 2: The Claim type, its sections, and its derived place

**Files:**
- Create: `kernel/src/Lips/Kernel/Claim.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Decision (Subject (..), Decision (..), Assertion (..))`, `Lips.Kernel.Engine.Value (Value (..), Piece (..), Ref (..), parseValue, sourceText, valueArtifactNames)`.
- Produces:
  ```haskell
  data ClaimPlace = PlaceDerivation | PlaceMachine deriving (Eq, Show)
  data Claim = Claim
    { clId     :: Text
    , clRun    :: Value
    , clStdin  :: Maybe Text
    , clStdout :: Maybe Text
    , clExit   :: Int
    , clPlace  :: ClaimPlace
    } deriving (Eq, Show)
  claimsFromDecisions :: [(Subject, Decision)] -> Either Text [Claim]
  claimPlace :: Value -> ClaimPlace
  comparisonPy :: Claim -> [Text]
  ```

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "claims (an observable the author stated)" $ do
    let dec subj asrt = Decision
          { dId = DecisionId "x", dSubject = Subject subj, dKind = Meta
          , dAssertion = Assertion asrt, dStrength = Stated
          , dProv = FromSource (SourceLoc "p.x.lips" 1), dRationale = Nothing }
        pair subj asrt = (Subject subj, dec subj asrt)
        vstr t = case parseValue t of Right v -> v; Left e -> error (T.unpack e)

    it "reads the closed section set, defaulting exit to 0" $
      claimsFromDecisions
        [ pair ["claim","echo","run"]    "\"${artifact.logscan}/bin/logscan --a 1\""
        , pair ["claim","echo","stdin"]  "\"{\\\"a\\\":1}\""
        , pair ["claim","echo","stdout"] "\"{\\\"a\\\":1}\""
        ]
        `shouldBe` Right
          [ Claim { clId = "echo"
                  , clRun = vstr "\"${artifact.logscan}/bin/logscan --a 1\""
                  , clStdin = Just "{\"a\":1}"
                  , clStdout = Just "{\"a\":1}"
                  , clExit = 0
                  , clPlace = PlaceDerivation } ]

    it "reads a stated exit code" $
      fmap (map clExit) (claimsFromDecisions
        [ pair ["claim","bad","run"]  "\"${artifact.logscan}/bin/logscan --nope\""
        , pair ["claim","bad","exit"] "2" ])
        `shouldBe` Right [2]

    it "refuses a section the grammar does not have" $
      claimsFromDecisions [ pair ["claim","echo","stderr"] "\"boom\"" ]
        `shouldBe` Left "claim echo: unknown section(s) stderr; a claim has run, stdin, stdout and exit"

    it "refuses a claim with no run" $
      claimsFromDecisions [ pair ["claim","echo","stdout"] "\"hi\"" ]
        `shouldBe` Left "claim echo: no run, so there is nothing to observe"

    it "places an artifact-only command in the nix sandbox" $
      claimPlace (vstr "\"${artifact.logscan}/bin/logscan --a 1\"") `shouldBe` PlaceDerivation

    it "places anything else in a booted machine" $ do
      claimPlace (vstr "\"systemctl is-active api\"") `shouldBe` PlaceMachine
      claimPlace (vstr "\"${pkgs.curl}/bin/curl -s localhost\"") `shouldBe` PlaceMachine

    it "compares exactly, stripping one trailing newline from the observed bytes" $
      comparisonPy Claim { clId = "echo", clRun = vstr "\"x\"", clStdin = Nothing
                         , clStdout = Just "hi", clExit = 0, clPlace = PlaceDerivation }
        `shouldBe`
          [ "expected_out = 'hi'"
          , "expected_exit = 0"
          , "if out.endswith('\\n'): out = out[:-1]"
          , "if code != expected_exit:"
          , "    raise SystemExit('claim echo: exit was %d, expected %d' % (code, expected_exit))"
          , "if out != expected_out:"
          , "    raise SystemExit('claim echo: stdout was %r, expected %r' % (out, expected_out))"
          ]
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL, module `Lips.Kernel.Claim` not found.

- [ ] **Step 3: Implement the module**

Create `kernel/src/Lips/Kernel/Claim.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | Claims: the one gate that observes a running thing instead of reading the
-- module text.
--
-- Every other gate lips has judges the MAP (an option assignment, a staged
-- path, a stamp). So a program whose behaviour lives in baked source could
-- state a sentence, have it minted into code, and then have that sentence
-- reworded or its implementation broken with every gate green. A claim closes
-- that by naming an observable the AUTHOR stated: a command, what it is fed,
-- what it must print, and how it must exit.
--
-- Nothing here is domain knowledge. @claim.\<id\>@ is a reserved emit head
-- beside @artifact.\<name\>@ -- build-group vocabulary, not a target option --
-- with a CLOSED section set, so an engine can fill it and cannot extend it. The
-- rhs stays in the closed value grammar, so a claim cannot compute.
--
-- The PLACE is derived, never declared: a command naming only artifacts runs as
-- a plain derivation in the nix sandbox (fast, no KVM, no network), anything
-- else runs inside a booted machine. So a CLI program never pays for a boot and
-- no new syntax carries the distinction.
module Lips.Kernel.Claim
  ( Claim (..)
  , ClaimPlace (..)
  , claimsFromDecisions
  , claimPlace
  , comparisonPy
  , claimRooted
  ) where

import           Data.List  (nub, sortOn)
import           Data.Maybe (fromMaybe)
import           Data.Text  (Text)
import qualified Data.Text  as T

import Lips.Kernel.Decision
import Lips.Kernel.Engine.Value (Piece (..), Ref (..), Value (..), sourceText,
                                 valueArtifactNames)

-- | Where a claim is observed. Derived from the command, not declared.
data ClaimPlace
  = -- | A plain derivation in the nix sandbox: the command names only
    --   artifacts, so nothing needs to boot.
    PlaceDerivation
  | -- | A booted machine (@nixosTest@): the command reaches beyond the
    --   program's own artifacts, so the module must actually run.
    PlaceMachine
  deriving (Eq, Show)

-- | One observable the author stated.
data Claim = Claim
  { clId     :: Text
  , clRun    :: Value        -- ^ the command; may hold @${artifact.\<name\>}@
  , clStdin  :: Maybe Text
  , clStdout :: Maybe Text
  , clExit   :: Int
  , clPlace  :: ClaimPlace
  }
  deriving (Eq, Show)

-- | Is this emit path the claim vocabulary? Twin of
-- 'Lips.Kernel.OptionType.artifactRooted': neither becomes a target option.
claimRooted :: [Text] -> Bool
claimRooted ("claim" : _) = True
claimRooted _             = False

-- | Gather the claims out of a ground base's @claim.\<id\>.\<section\>@
-- decisions. Deterministic (ordered by id). Every defect is a loud 'Left' in
-- plain words: a section the grammar does not have (so a mint's typo cannot be
-- silently dropped), a claim with no command, a non-text stdin\/stdout, or a
-- non-integer exit.
claimsFromDecisions :: [(Subject, Decision)] -> Either Text [Claim]
claimsFromDecisions winners = traverse one (sortOn fst grouped)
  where
    grouped =
      [ (cid, [ (sec, d) | (Subject ("claim" : c : sec : _), d) <- claims, c == cid ])
      | cid <- nub [ c | (Subject ("claim" : c : _ : _), _) <- claims ] ]
    claims = [ sd | sd@(Subject ("claim" : _), _) <- winners ]
    one (cid, parts) = do
      case nub [ s | (s, _) <- parts, s `notElem` ["run", "stdin", "stdout", "exit"] ] of
        []   -> Right ()
        secs -> Left ("claim " <> cid <> ": unknown section(s) " <> T.intercalate ", " secs
                       <> "; a claim has run, stdin, stdout and exit")
      runV <- case valueOf "run" of
        Just v  -> Right v
        Nothing -> Left ("claim " <> cid <> ": no run, so there is nothing to observe")
      inT  <- traverse (text "stdin") (valueOf "stdin")
      outT <- traverse (text "stdout") (valueOf "stdout")
      code <- case valueOf "exit" of
        Nothing         -> Right 0
        Just (VInt n)   -> Right (fromIntegral n)
        Just v          -> Left ("claim " <> cid <> ": exit must be an integer, got "
                                  <> T.pack (show v))
      Right Claim { clId = cid, clRun = runV, clStdin = inT, clStdout = outT
                  , clExit = code, clPlace = claimPlace runV }
      where
        valueOf sec = lookup sec [ (s, parsed d) | (s, d) <- parts ]
        parsed d = case dAssertion d of Assertion a -> unsafeValue cid a
        text sec v = case sourceText v of
          Just t  -> Right t
          Nothing -> Left ("claim " <> cid <> ": " <> sec <> " must be plain text, got "
                            <> T.pack (show v))

-- | A ground assertion is canonical 'Value' text by construction (stored by
-- @fillValue@), so a parse failure here is an engine defect the caller already
-- reports as 'RMalformed'; keeping the parse total keeps this module pure in
-- (subject, assertion) with no error channel of its own for that case.
unsafeValue :: Text -> Text -> Value
unsafeValue _ a = fromMaybe (VStr [PLit a]) (either (const Nothing) Just (parseValueE a))
  where parseValueE = Lips.Kernel.Engine.Value.parseValue

-- | The place, derived: only artifact references (and literals) keep a claim in
-- the sandbox. A package reference or a bare command needs the booted system,
-- since the thing it observes is the running module, not a build.
claimPlace :: Value -> ClaimPlace
claimPlace v
  | onlyArtifacts v = PlaceDerivation
  | otherwise       = PlaceMachine
  where
    onlyArtifacts (VStr ps) = all litOrArt ps && not (null (valueArtifactNames (VStr ps)))
    onlyArtifacts _         = False
    litOrArt (PLit _) = True
    litOrArt (PArt _) = True
    litOrArt _        = False

-- | The comparison, as python lines over @out@ (the observed stdout, a str) and
-- @code@ (the observed exit status, an int).
--
-- One implementation for both places: a @nixosTest@ script is python already,
-- so rendering the comparison once and reusing it is what keeps a sandbox claim
-- and a machine claim from judging by different rules. EXACT, with exactly one
-- trailing newline stripped: a program that prints a line ends it in @\\n@,
-- while the author states the line. Containment is deliberately absent -- it is
-- what let a minted @"200\\n404"@ pass as @"200n404"@ unseen.
comparisonPy :: Claim -> [Text]
comparisonPy c =
  [ "expected_out = " <> pyStr (fromMaybe "" (clStdout c))
  , "expected_exit = " <> T.pack (show (clExit c))
  , "if out.endswith('\\n'): out = out[:-1]"
  , "if code != expected_exit:"
  , "    raise SystemExit('claim " <> clId c <> ": exit was %d, expected %d' % (code, expected_exit))"
  ] ++
  [ l | Just _ <- [clStdout c]
      , l <- [ "if out != expected_out:"
             , "    raise SystemExit('claim " <> clId c
                 <> ": stdout was %r, expected %r' % (out, expected_out))" ] ]

-- | A python single-quoted literal: only @\\@ and @'@ need escaping, and a
-- newline is written as an escape so the rendered line stays one line.
pyStr :: Text -> Text
pyStr t = "'" <> T.concatMap esc t <> "'"
  where
    esc '\\' = "\\\\"
    esc '\'' = "\\'"
    esc '\n' = "\\n"
    esc ch   = T.singleton ch
```

Fix the `unsafeValue` shim while implementing: import `parseValue` normally at
the top (`import Lips.Kernel.Engine.Value (..., parseValue, ...)`) and write

```haskell
    parsed d = case dAssertion d of
      Assertion a -> either (const (VStr [PLit a])) id (parseValue a)
```

inline, deleting the `unsafeValue` helper and its qualified reference — a ground
assertion always re-parses, and the fallback keeps this module total.

Register the module in the cabal file's `exposed-modules` (find it with
`grep -n "Kernel.Source" kernel/*.cabal`).

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS, `-Wall` clean (no unused imports left from the shim).

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Claim.hs kernel/*.cabal kernel/test/Spec.hs
git commit -m "claim: the closed grammar of an observable, with its place derived"
```

### Task 3: Project claims from the ground base, and keep them out of the module

**Files:**
- Modify: `kernel/src/Lips/Kernel/Realize.hs` (add `realizeClaims`; exclude the claim root from option assignments)
- Modify: `kernel/src/Lips/Kernel/Run.hs` (`Realization` gains `rlClaims`)
- Modify: `kernel/src/Lips/Kernel/OptionType.hs` (admissibility skips the claim root)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Claim (Claim (..), ClaimPlace (..), claimsFromDecisions, claimRooted)`.
- Produces:
  ```haskell
  realizeClaims :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                -> Base -> Either RealizeError [Claim]
  -- Realization gains: rlClaims :: [Claim]
  ```

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "claims reach the realization, never the module" $ do
    let lang = T.unlines
          [ "p1 meta lang.pattern.p1 stated \"install it as <name> => fact cmd.<name>.name \\\"<name>\\\"\""
          , "p2 meta lang.pattern.p2 stated \"given <in> it prints <out> => fact witness.<in>.out \\\"<out>\\\"\""
          ]
    -- Build the engine through the ordinary door (parseRuleBody), then realize a
    -- base holding one claim group and one option, and assert both sides.
    it "excludes claim decisions from the rendered module" $ do
      let ground = fromList
            [ groundDec ["claim","echo","run"] "\"${artifact.tool}/bin/tool\""
            , groundDec ["artifact","tool","builder"] "\"buildGoModule\""
            , groundDec ["environment","systemPackages"] "[ ${artifact.tool} ]"
            ]
      case realize (const Replace) assembleSubject ground of
        Left e    -> expectationFailure (show e)
        Right txt -> do
          txt `shouldNotSatisfy` T.isInfixOf "claim"
          txt `shouldSatisfy` T.isInfixOf "environment.systemPackages"

    it "projects the claim out of the same ground base" $ do
      let ground = fromList
            [ groundDec ["claim","echo","run"] "\"${artifact.tool}/bin/tool\""
            , groundDec ["claim","echo","stdout"] "\"hi\""
            , groundDec ["artifact","tool","builder"] "\"buildGoModule\""
            ]
      fmap (map clId) (realizeClaims (const Replace) assembleSubject ground)
        `shouldBe` Right ["echo"]
```

Add the helper beside the other test helpers:

```haskell
groundDec :: [Text] -> Text -> Decision
groundDec subj asrt = Decision
  { dId = DecisionId (T.intercalate "." subj), dSubject = Subject subj, dKind = Meta
  , dAssertion = Assertion asrt, dStrength = Stated
  , dProv = FromSource (SourceLoc "t.x.lips" 1), dRationale = Nothing }
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL — `realizeClaims` not in scope, and the module test fails
because claim decisions currently render as option assignments.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Kernel/Realize.hs`:

1. Export `realizeClaims`; import `Lips.Kernel.Claim (Claim, claimsFromDecisions, claimRooted)`.
2. Replace the option/artifact split in `renderModule` so a claim is neither:

```haskell
renderModule winners = do
  let (arts, rest) = partition (rootedAtArtifact . fst) winners
      -- A claim is build-group vocabulary like an artifact: it is observed, not
      -- assigned, so it must not become an option. Without this it renders as
      -- `claim.echo.run = "...";`, a path no target world declares.
      opts = [ sd | sd@(Subject segs, _) <- rest, not (claimRooted segs) ]
      defined = [ n | (Subject ("artifact" : n : _), _) <- arts ]
  ...
```

3. Do the same in `realizeArtifactFile`'s `arts` filter (already artifact-only,
   so no change needed) and add the projection:

```haskell
-- | The claims a ground base states: the observables the author supplied,
-- projected exactly like the artifacts beside them (same resolve, same base),
-- so what @check@ runs and what the module contains can never disagree.
realizeClaims :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
              -> Base -> Either RealizeError [Claim]
realizeClaims modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> case claimsFromDecisions (Map.toList winners) of
      Right cs -> Right cs
      Left why -> Left (RBadClaim why)
```

4. Add the error case to `RealizeError`:

```haskell
  | -- | A malformed claim group, in plain words (an unknown section, a claim
    --   with no command, a non-text stdin/stdout).
    RBadClaim Text
```

In `kernel/src/Lips/Kernel/Run.hs`:

5. Add `rlClaims :: [Claim]` to `Realization` (documented: "the observables the
   program states; empty for a program that states none"), extend `runBase`'s
   applicative chain with `<*> realizeClaims modeOf assemble ground`, and map
   the new error in `fromRealizeError`:

```haskell
fromRealizeError (RBadClaim why) = Unrealizable [why]
```

In `kernel/src/Lips/Kernel/OptionType.hs`:

6. Generalize the admissibility skip so a claim path is never grounded against
   the target schema:

```haskell
-- | An emit rooted at @artifact@ or @claim@ is the kernel's own vocabulary: the
-- first becomes a @let@-bound derivation, the second an experiment @check@ runs.
-- Neither is a target option, so the option schema does not constrain it.
reservedRoot :: [Text] -> Bool
reservedRoot ("artifact" : _) = True
reservedRoot ("claim" : _)    = True
reservedRoot _                = False
```

Keep `artifactRooted` as-is only if something outside still calls it
(`grep -rn artifactRooted kernel/`); otherwise rename the call site in
`checkEmits` to `reservedRoot` and export that instead.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Realize.hs kernel/src/Lips/Kernel/Run.hs kernel/src/Lips/Kernel/OptionType.hs kernel/test/Spec.hs
git commit -m "realize: project claims beside artifacts, and keep both out of the option namespace"
```

### Task 4: Render `claims.nix`

**Files:**
- Create: `kernel/src/Lips/Nix/Claims.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Claim (Claim (..), ClaimPlace (..), comparisonPy)`, `Lips.Kernel.Engine.Value (renderRealized)`, `Lips.Nix.Target (Target (..))`.
- Produces:
  ```haskell
  claimsFile :: [Claim] -> Maybe Text   -- Nothing when the program states no claims
  ```

- [ ] **Step 1: Write the failing test**

```haskell
  describe "claims.nix (the experiments, as nix)" $ do
    let vstr t = case parseValue t of Right v -> v; Left e -> error (T.unpack e)
        derivClaim = Claim { clId = "echo"
                           , clRun = vstr "\"${artifact.tool}/bin/tool --a 1\""
                           , clStdin = Just "{\"a\":1}", clStdout = Just "{\"a\":1}"
                           , clExit = 0, clPlace = PlaceDerivation }
        machineClaim = Claim { clId = "alive", clRun = vstr "\"systemctl is-active api\""
                             , clStdin = Nothing, clStdout = Just "active"
                             , clExit = 0, clPlace = PlaceMachine }

    it "writes nothing for a program that states no claims" $
      claimsFile [] `shouldBe` Nothing

    it "renders a sandbox claim as a derivation that runs the command" $ do
      let Just txt = claimsFile [derivClaim]
      txt `shouldSatisfy` T.isInfixOf "artifact = import ./artifact.nix { inherit pkgs; };"
      txt `shouldSatisfy` T.isInfixOf "echo = pkgs.runCommand \"claim-echo\""
      txt `shouldSatisfy` T.isInfixOf "${artifact.tool}/bin/tool --a 1"
      txt `shouldSatisfy` T.isInfixOf "if out.endswith('\\n'): out = out[:-1]"
      txt `shouldNotSatisfy` T.isInfixOf "nixosTest"

    it "renders a machine claim as a nixosTest importing the module" $ do
      let Just txt = claimsFile [machineClaim]
      txt `shouldSatisfy` T.isInfixOf "pkgs.nixosTest"
      txt `shouldSatisfy` T.isInfixOf "imports = [ ./default.nix ];"
      txt `shouldSatisfy` T.isInfixOf "machine.execute("

    it "is deterministic in claim order" $
      claimsFile [machineClaim, derivClaim] `shouldBe` claimsFile [machineClaim, derivClaim]
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL, module `Lips.Nix.Claims` not found.

- [ ] **Step 3: Implement**

Create `kernel/src/Lips/Nix/Claims.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | @claims.nix@: the program's stated observables as buildable experiments.
--
-- Rendered beside @artifact.nix@ from the SAME ground base, so what @check@
-- runs and what the module contains cannot disagree. Two shapes, chosen by the
-- claim's derived place and nothing else:
--
--   * 'PlaceDerivation' -- @runCommand@: run the command in the nix sandbox,
--     capture stdout and status, judge. No boot, no KVM, no network.
--   * 'PlaceMachine' -- @nixosTest@: boot the realized module and run the
--     command inside the machine, then judge with the same comparison.
--
-- Both judge with 'comparisonPy', so exactness is implemented once.
module Lips.Nix.Claims (claimsFile) where

import           Data.List (sortOn)
import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Kernel.Claim        (Claim (..), ClaimPlace (..), comparisonPy)
import Lips.Kernel.Engine.Value (renderRealized)

-- | The file, or 'Nothing' when the program states no claims (so a claim-free
-- compile writes nothing and its output stays byte-identical).
claimsFile :: [Claim] -> Maybe Text
claimsFile [] = Nothing
claimsFile cs = Just $ T.unlines $
  [ "# lips-realized claims. Generated from a ground decision base; do not edit."
  , "{ pkgs }:"
  , "let"
  , "  artifact = import ./artifact.nix { inherit pkgs; };"
  , "in {"
  ] ++ concatMap entry (sortOn clId cs) ++ [ "}" ]

entry :: Claim -> [Text]
entry c = case clPlace c of
  PlaceDerivation ->
    [ "  " <> clId c <> " = pkgs.runCommand \"claim-" <> clId c <> "\""
    , "    { nativeBuildInputs = [ pkgs.python3 ]; }"
    , "    ''"
    , "      cat > cmd <<'LIPS_CMD'"
    , "      " <> command c
    , "      LIPS_CMD"
    , "      cat > stdin <<'LIPS_STDIN'"
    ] ++ map ("      " <>) (T.lines (stdinText c)) ++
    [ "      LIPS_STDIN"
    , "      set +e"
    , "      sh cmd < stdin > out 2> err"
    , "      echo $? > code"
    , "      set -e"
    , "      python3 judge.py"
    , "      touch $out"
    , "    ''"
    , "    # judge.py is written by the same derivation, so the comparison text"
    , "    # lives in one place for both claim places."
    ] ++ judgeFile c
  PlaceMachine ->
    [ "  " <> clId c <> " = pkgs.nixosTest {"
    , "    name = \"claim-" <> clId c <> "\";"
    , "    nodes.machine = { imports = [ ./default.nix ]; };"
    , "    testScript = ''"
    , "      machine.wait_for_unit(\"multi-user.target\")"
    , "      code, out = machine.execute(" <> pyCommand c <> ")"
    ] ++ map ("      " <>) (comparisonPy c) ++
    [ "    '';"
    , "  };"
    ]

-- | The command as shell text: the claim's value realized (an
-- @${artifact.<name>}@ piece becomes a nix interpolation, which the surrounding
-- indented string resolves against the @artifact@ binding above).
command :: Claim -> Text
command c = unquote (renderRealized (clRun c))
  where
    unquote t = case T.stripPrefix "\"" t >>= T.stripSuffix "\"" of
      Just inner -> inner
      Nothing    -> t

stdinText :: Claim -> Text
stdinText c = maybe "" id (clStdin c)

-- | The machine form: the command and its stdin as one python call. stdin is
-- fed by a here-string so the machine needs no staged file.
pyCommand :: Claim -> Text
pyCommand c = case clStdin c of
  Nothing -> "\"" <> command c <> "\""
  Just s  -> "\"\"\"" <> command c <> " <<'LIPS_STDIN'\n" <> s <> "\nLIPS_STDIN\"\"\""

-- | The sandbox judge: write the comparison to a file the builder runs, reading
-- the captured bytes and status.
judgeFile :: Claim -> [Text]
judgeFile c =
  [ "    # (written inline above)" ]
  -- Implementation note for the engineer: emit judge.py from inside the same
  -- runCommand body rather than as a separate attribute, by prepending these
  -- lines to the builder script before `sh cmd`:
  --   cat > judge.py <<'LIPS_JUDGE'
  --   out = open('out').read()
  --   code = int(open('code').read().strip())
  --   <comparisonPy c>
  --   LIPS_JUDGE
```

Finish `judgeFile` as the note describes: it returns the here-doc lines and
`entry` places them BEFORE `sh cmd < stdin`, so the builder reads:

```
cat > judge.py <<'LIPS_JUDGE'
out = open('out').read()
code = int(open('code').read().strip())
<comparisonPy c lines>
LIPS_JUDGE
```

Then delete the placeholder comment lines. Register the module in the cabal
file.

- [ ] **Step 4: Run to verify pass, then eyeball one rendering**

Run: `just test`
Then, to read a rendering by hand:

```bash
nix develop -c bash -c 'cd kernel && ghci -isrc -e "putStrLn . maybe \"\" Data.Text.unpack =<< pure (Lips.Nix.Claims.claimsFile [])" 2>/dev/null || true'
```
(The suite's `shouldSatisfy` assertions are the real gate; skip the ghci step if
it fights the sandbox.)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Nix/Claims.hs kernel/*.cabal kernel/test/Spec.hs
git commit -m "claims.nix: render each stated observable as a buildable experiment"
```

### Task 5: The `#claims` flake rung

**Files:**
- Modify: `kernel/src/Lips/Nix/Flake.hs` (`flakeText` and `runCommands` gain the claims dimension)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  flakeText   :: Target -> Bool -> Bool -> Text        -- hasArtifacts, hasClaims
  runCommands :: Target -> [Text] -> Bool -> FilePath -> [Text]  -- artNames, hasClaims, dir
  ```

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "the claims rung" $ do
    it "exposes an aggregate claims package when the program states claims" $ do
      let txt = flakeText Nixos True True
      txt `shouldSatisfy` T.isInfixOf "claims = pkgs.linkFarmFromDrvs \"claims\""
      txt `shouldSatisfy` T.isInfixOf "import ./claims.nix { pkgs = pkgsFor system; }"

    it "leaves a claim-free flake byte-identical to before" $
      flakeText Nixos True False `shouldBe` flakeTextLegacyNixosWithArtifacts

    it "prints the build command only when there are claims" $ do
      runCommands Nixos [] True "/tmp/out"
        `shouldSatisfy` any (T.isInfixOf "#claims")
      runCommands Nixos [] False "/tmp/out"
        `shouldNotSatisfy` any (T.isInfixOf "#claims")
```

For `flakeTextLegacyNixosWithArtifacts`, capture today's output first:
run the existing suite's flake test, or bind it as
`let flakeTextLegacyNixosWithArtifacts = flakeText Nixos True False` AFTER the
change and instead assert the weaker but sufficient property:

```haskell
    it "leaves a claim-free flake free of claim vocabulary" $
      flakeText Nixos True False `shouldNotSatisfy` T.isInfixOf "claims"
```

Use the second form (no golden file to maintain).

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL, `flakeText` applied to too many arguments.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Nix/Flake.hs`:

```haskell
flakeText :: Target -> Bool -> Bool -> Text
flakeText target hasArtifacts hasClaims = T.unlines $
  ... ++ packagesOutput target hasArtifacts hasClaims ++ ...
```

and in `packagesOutput`, add:

```haskell
    claimLine
      -- One aggregate so `nix build <dir>#claims` runs EVERY experiment: a
      -- claim that is not built is a claim that did not run, and "not verified"
      -- must never render as verified.
      | hasClaims = [ "        claims = (pkgsFor system).linkFarmFromDrvs \"claims\""
                    , "          (builtins.attrValues (import ./claims.nix { pkgs = pkgsFor system; }));" ]
      | otherwise = []
```

In `runCommands`, take `hasClaims` and append (for every world, since a
derivation claim is world-neutral):

```haskell
    claimLines
      | hasClaims = [ cmd "run the claims" "build" (ref "claims") "   (what the program says it does)" ]
      | otherwise = []
```

Update the three call sites the compiler names (`kernel/app/Main.hs`, and the
existing `Spec.hs` flake tests) to pass the new argument.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Nix/Flake.hs kernel/test/Spec.hs kernel/app/Main.hs
git commit -m "flake: expose #claims, one aggregate that runs every experiment"
```

### Task 6: `compile` writes the claims; `check` builds them

**Files:**
- Modify: `kernel/app/Main.hs` (`compileLoose`, `checkLoose`)
- Test: manual (an end-to-end command), plus the suite stays green

- [ ] **Step 1: Write `claims.nix` at compile**

In `compileLoose`, after the `artifact.nix` write:

```haskell
  hasClaims <- case claimsFile (rlClaims rl) of
    Nothing   -> pure False
    Just body -> TIO.writeFile (outDirPath </> "claims.nix") body >> pure True
  TIO.writeFile (outDirPath </> "flake.nix") (flakeText target (not (null artNames)) hasClaims)
  ...
  mapM_ (TIO.hPutStrLn stderr) (runCommands target artNames hasClaims outDirPath)
```

Import `Lips.Nix.Claims (claimsFile)`.

- [ ] **Step 2: Build the claims in `check`**

In `checkLoose`, after the expect gate succeeds, add a claim gate. It builds the
compiled directory's `#claims`, so it needs the compiled tree: reuse the temp
staging `expectGate` already performs (read `expectGate` at Main.hs:247 and
follow its temp-dir shape), writing `claims.nix`, `artifact.nix`, `default.nix`,
the staged+filled `artifacts/`, and a `flake.nix`, then:

```haskell
-- | The claim gate: every observable the program states must actually hold.
--
-- This is the ONE gate that observes a running thing. A sandbox claim is a
-- plain build; a machine claim boots the module, so it needs KVM. A claim that
-- cannot run is a LOUD failure naming the remedy, never a skip: "not verified"
-- must never render as verified.
claimGate :: FilePath -> FilePath -> Realization -> IO ()
claimGate file dir rl
  | null (rlClaims rl) = pure ()
  | otherwise = do
      kvm <- doesPathExist "/dev/kvm"
      let machine = [ clId c | c <- rlClaims rl, clPlace c == PlaceMachine ]
      when (not kvm && not (null machine)) $ die (report
        (T.pack file <> " states " <> plural (length machine) "claim"
          <> " that must be observed in a booted machine, and this host has no /dev/kvm.")
        machine
        "\8594 run it on a host with KVM, or state the observable over the program's own binary instead.")
      res <- try (readProcessWithExitCode "nix"
        ["build", "--no-link", "path:" <> dir <> "#claims"] "")
      case res of
        Left e -> die (nixMissing file "run the claims it states" "check" (tshow (e :: IOException)))
        Right (ExitFailure _, _, err) -> die (report
          (T.pack file <> ": what the program says it does is not what it does.")
          (T.lines (T.pack err))
          ("\8594 the behaviour lives in minted source, so rebuild it: lips generate " <> T.pack file))
        Right (ExitSuccess, _, _) ->
          TIO.hPutStrLn stderr ("all " <> tshow (length (rlClaims rl)) <> " claims hold.")
```

Call it from `checkLoose` after the expect gate, and skip it under
`--no-contract` (the same caller that cannot evaluate cannot build either).

- [ ] **Step 3: Verify the suite and the corpus still pass**

Run: `just test`
Then: `just check-expect`
Expected: green. No committed engine states a claim yet, so `claimGate` is a
no-op for all of them and `check` stays nixpkgs-free for them.

- [ ] **Step 4: Verify by hand that compile is unchanged for a claim-free program**

```bash
git add -A && nix run . -- compile examples/ledger.backup.lips
ls examples/backup/out/ledger        # no claims.nix
```
Expected: no `claims.nix`, and the printed rungs carry no `#claims`.

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "check: build the claims a program states, loud when a machine claim has no KVM"
```

### Task 7: `.expect` pins claim slots

**Files:**
- Modify: `kernel/src/Lips/Kernel/Expect.hs` (`isArtifactExpect` generalizes)
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`uncheckableExpects` follows)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `isGroundExpect :: Expect -> Bool` (replaces `isArtifactExpect`; keep the old name as a deprecated alias only if a caller outside the repo needs it — inside, rename every call site).

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "a contract pins a claim slot" $ do
    let ex p = Expect { exId = "e1", exPath = p, exFrom = Subject ["w"], exToken = Nothing }
    it "judges a claim slot against the ground base, with no eval" $ do
      isGroundExpect (ex ["claim","echo","stdout"]) `shouldBe` True
      isGroundExpect (ex ["artifact","tool","args","pname"]) `shouldBe` True
      isGroundExpect (ex ["environment","systemPackages"]) `shouldBe` False

    it "names a claim slot nothing realizes" $
      checkArtifactValues (fromList [])
        [ (ex ["claim","echo","stdout"], "hi") ]
        `shouldSatisfy` any (T.isInfixOf "nothing realizes this slot")

    it "keeps a claim expect out of the nix eval set" $
      uncheckableExpects [] [ex ["claim","echo","stdout"]] `shouldBe` []
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL, `isGroundExpect` not in scope.

- [ ] **Step 3: Implement**

In `Expect.hs`, replace `isArtifactExpect` with:

```haskell
-- | Does this assertion name a slot the KERNEL realizes (an artifact arg, a
-- claim section) rather than a target option? Such a slot is never an attribute
-- of the module a caller can evaluate -- an artifact arg is consumed by a
-- builder, a claim section by an experiment -- but it IS a literal in the
-- realized output, so the kernel judges it itself: no nix, no eval. This is
-- what lets an artifact-only or claim-bearing engine pin anything at all.
isGroundExpect :: Expect -> Bool
isGroundExpect e = case exPath e of
  ("artifact" : _) -> True
  ("claim" : _)    -> True
  _                -> False
```

Rename every call site (`grep -rn isArtifactExpect kernel/`) — `Minting.hs`'s
`uncheckableExpects` and `Main.hs`'s `runExpects` partition.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/Expect.hs kernel/src/Lips/Generate/Minting.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "expect: a claim slot is pinned like an artifact slot, judged against the ground base"
```

### Task 8: The generate obligation

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (pure predicates)
- Modify: `kernel/app/Main.hs` (`generate` refuses; runs sandbox claims at the gate)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  -- Minting.hs
  claimlessBakedSource :: [SourceFile] -> [Claim] -> Bool
  -- ^ True when the mint bakes source and states no observable at all.
  unplaceableClaims :: Target -> [Claim] -> [Text]
  -- ^ the ids of machine claims minted for a world with no machine to boot.
  ```

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "the mint owes an observable where it bakes source" $ do
    let src = SourceFile { sfArtifact = "tool", sfPath = "main.go", sfContent = "package main" }
        vstr t = case parseValue t of Right v -> v; Left e -> error (T.unpack e)
        derivC = Claim "echo" (vstr "\"${artifact.tool}/bin/tool\"") Nothing (Just "hi") 0 PlaceDerivation
        machC  = Claim "alive" (vstr "\"systemctl is-active api\"") Nothing (Just "active") 0 PlaceMachine

    it "refuses baked source with no claim" $
      claimlessBakedSource [src] [] `shouldBe` True

    it "admits baked source with one claim" $
      claimlessBakedSource [src] [derivC] `shouldBe` False

    it "leaves a pure-config mint unaffected" $
      claimlessBakedSource [] [] `shouldBe` False

    it "refuses a machine claim in a world with no machine" $ do
      unplaceableClaims Kubenix [machC] `shouldBe` ["alive"]
      unplaceableClaims Kubenix [derivC] `shouldBe` []
      unplaceableClaims Nixos [machC] `shouldBe` []
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL, predicates not in scope.

- [ ] **Step 3: Implement the predicates**

In `Minting.hs` (export both):

```haskell
-- | A mint that BAKES source and states no observable is refused. Where the
-- behaviour lives in minted code, the module text says nothing about what that
-- code does, so without an experiment nothing holds the implementation -- or any
-- future re-mint -- to the author's words. A pure-config mint is unaffected: its
-- behaviour IS its option assignments, which the contract already pins.
claimlessBakedSource :: [SourceFile] -> [Claim] -> Bool
claimlessBakedSource sources claims = not (null sources) && null claims

-- | The claims a world cannot observe: a machine claim needs a bootable
-- machine, which only the NixOS world has. Refused at the gate rather than at
-- some later check, so an engine that cannot be verified is never written.
unplaceableClaims :: Target -> [Claim] -> [Text]
unplaceableClaims Nixos _ = []
unplaceableClaims _ cs    = [ clId c | c <- cs, clPlace c == PlaceMachine ]
```

- [ ] **Step 4: Refuse at the gate, and run the sandbox claims**

In `Main.hs`'s `generate`, beside `artifactGate`, add:

```haskell
-- | The claim gate at mint time: an engine whose stated observables do not hold
-- is never written. Sandbox claims are built here (the same nixpkgs the
-- artifact gate uses, so the mint observes the world it was grounded against); a
-- machine claim needs KVM, and without it the mint refuses rather than admitting
-- an unverified engine.
```

and wire the refusals into the existing refusal path (`refusalReport` /
`die`), naming:
- `claimlessBakedSource` → "this engine bakes source but states no observable"
  with the remedy "state an example in the program (\"given X, print Y\") and
  mint again";
- `unplaceableClaims` → "claim <id> must be observed in a booted machine, and
  the <world> world has none".

Reuse `buildArtifact`'s shape for building `#claims`-equivalent derivations at
mint: write `claims.nix` into the same temp dir `artifactGate` builds in, and
build each sandbox claim attribute with the pinned nixpkgs.

- [ ] **Step 5: Run to verify pass**

Run: `just test`
Expected: PASS. `just check-expect` too (no committed engine bakes source
without... — note: `logscan`, `board`, `habit`, `http`, `function`, `website`
DO bake source and state no claims. The obligation applies at GENERATE only,
never at compile/check, so the committed corpus stays green until Milestone 3
re-mints them. Verify that: `just check-expect` must still pass.)

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Generate/Minting.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "generate: an engine that bakes source owes an observable, and a claim must be placeable in its world"
```

### Task 9: The advisory LSP diagnostic

**Files:**
- Modify: `kernel/src/Lips/Lsp/Derive.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Diagnosis (diagInert)`, the program's realized claims (or, where the LSP has no realization, the engine's claim-emitting rules).
- Produces: one warning per concept-only line, in a baked-source language whose program states no claim: `"nothing observes this sentence: state an example so a claim can hold the built source to it"`.

- [ ] **Step 1: Write the failing test**

Read `kernel/src/Lips/Lsp/Derive.hs` for the exact diagnostic type and
constructor first, then mirror the existing `diagInert` test:

```haskell
  describe "the LSP says when a sentence is observed by nothing" $ do
    it "warns on a concept-only line where the language bakes source and states no claim" $
      -- same shape as the existing diagInert diagnostic test, with
      -- bakesSource = True and claims = []
      pending

    it "stays silent when the program states a claim" $ pending
```

Replace both `pending`s with the concrete assertions once the neighbouring
test's helpers are in view (they build an `EngineData` and a program text).

- [ ] **Step 2: Run to verify failure (pending → real failure)**

Run: `just test`
Expected: the two new examples fail.

- [ ] **Step 3: Implement**

Add the warning beside the inert-line diagnostic. Gate it on two facts, both
already available: the language bakes source, and no rule emits a `claim.*`
path. Keep it a WARNING (advisory), never an error: the remedy is an author
writing an example, and TODO 2b's shape has no static gate.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Lsp/Derive.hs kernel/test/Spec.hs
git commit -m "lsp: warn where a sentence reaches baked source and no observable"
```

### Task 10: Teach the mint the claim grammar

**Files:**
- Modify: `assets/mint/body.md` (the domain-blind physics: the head, the sections, the exact comparison, the obligation)
- Modify: `assets/mint/nixos.md` (machine claims exist here)
- Modify: `assets/mint/kubenix.md`, `assets/mint/terranix.md`, `assets/mint/home-manager.md` (only artifact-only claims exist here)
- Test: `kernel/test/Spec.hs` (the prompt is embedded, so pin the new section's presence)

- [ ] **Step 1: Write the failing test**

```haskell
  describe "the mint prompt states the claim grammar" $ do
    it "names the head and its sections" $ do
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "claim.<id>.run"
      systemPromptFor Nixos `shouldSatisfy` T.isInfixOf "claim.<id>.stdout"
    it "states the world limit where there is no machine" $
      systemPromptFor Kubenix `shouldSatisfy` T.isInfixOf "no machine to boot"
```

- [ ] **Step 2: Run to verify failure**

Run: `just test`
Expected: FAIL.

- [ ] **Step 3: Write the prompt section**

In `assets/mint/body.md`, add a section in the existing voice, stating:
the author writes the example sentence; a pattern crystallizes it and a rule
emits `claim.<id>.run` / `.stdin` / `.stdout` / `.exit` (default 0);
the run may hold `${artifact.<name>}`; comparison is exact, with exactly one
trailing newline stripped from the observed output, so state the printed line
without its newline; a claim cannot compute; where the engine bakes source it
must state at least one claim; never invent a witness — if the program states
no example, file a gap instead.

In `nixos.md`: a command that reaches beyond the program's own artifacts is
observed inside a booted machine.
In the other three world files: only a command over `${artifact.<name>}` can be
observed here, since there is **no machine to boot** in this world.

- [ ] **Step 4: Run to verify pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/mint kernel/test/Spec.hs
git commit -m "mint: state the claim grammar, its exact comparison, and its world limit"
```

---

## Milestone 3 — Re-Mint the Four

### Task 11: Add witnesses and re-mint `logscan`, `board`, `habit`, `hello.http`

**Files:**
- Modify: `examples/logscan.lips`, `examples/board.lips`, `examples/habit.lips`, `examples/hello.http.lips`
- Regenerate (machine-written): `examples/<language>/<language>.lang`, `.expect`, `.generation`, `README.md`, `artifacts/`
- Modify: `DESIGN.md` §13, `TODO.md`

**Note for the executing agent:** `generate` needs `pi` on PATH with provider
auth, and the `hello.http` machine claim needs KVM. If the sandbox denies
either, STOP and hand these commands to the human rather than working around
them; a mint is not something to fake.

- [ ] **Step 1: Add one witness sentence per program**

Each program gains an example line in its own words, e.g. for
`examples/logscan.lips`:

```
given the line {"a":1,"b":2} and the argument --a 1, print it unchanged.
```

Keep the wording plain and in the program's existing voice. Every witness must
be observable over the program's own binary (a sandbox claim) except
`hello.http.lips`, whose witness names the running service (a machine claim).

- [ ] **Step 2: Re-mint one language and read what it wrote**

```bash
git add -A
nix run . -- generate --renew --model anthropic/claude-opus-5 examples/logscan.lips
```
Expected: the mint writes a `claim.*`-emitting rule, the gate builds and runs
it, and the engine is accepted. Read `examples/logscan/logscan.lang` and
`README.md` before continuing.

- [ ] **Step 3: Verify the claim actually runs**

```bash
git add -A
nix run . -- check examples/logscan.lips
nix run . -- compile examples/logscan.lips     # prints the #claims rung
nix build path:examples/logscan/out/logscan#claims --no-link
```
Expected: "all N claims hold"; the build succeeds.

- [ ] **Step 4: Prove the claim can fail**

Edit the witness's expected output in `examples/logscan.lips` to something
false (e.g. change a printed field), then:

```bash
git add -A && nix run . -- check examples/logscan.lips
```
Expected: LOUD failure naming the claim, the expected and the observed value.
Revert the edit afterwards.

- [ ] **Step 5: Commit this language**

```bash
git add examples/logscan.lips examples/logscan
git commit -m "logscan: state an observable and re-mint against it"
```

- [ ] **Step 6: Repeat steps 1-5 for `board`, `habit`, `hello.http`**

One commit per language. `hello.http.lips` needs KVM for its machine claim; run
`just ci` after it lands.

- [ ] **Step 7: Full suite**

```bash
just test
just check-expect
just ci          # needs KVM
```
Expected: all green.

- [ ] **Step 8: Update the ledger and the TODO**

In `DESIGN.md` §13, add the milestone entries: the source-spec verdict (what it
closes, and the corrected diagnosis — the reword hole was narrower than TODO
recorded), claims (grammar, derived place, entry point, obligation, the
`check`-needs-nixpkgs deviation), and the four re-mints. In `TODO.md`, drop
item 1 and the parts of 2a(iii), 2a(iv) and 2b it closes; leave 2b's advisory
half recorded as advisory.

- [ ] **Step 9: Commit**

```bash
git add DESIGN.md TODO.md
git commit -m "design: record the meaning dimension in the ledger"
```

---

## Self-Review

**Spec coverage.** Milestone 1 (§"Milestone 1"): Task 1. Claim
representation and reserved head: Tasks 2, 3. Projection and place: Tasks 2, 3.
Entry point (`compile` writes, `check` builds, loud without KVM): Tasks 4, 5, 6.
`.expect` pinning: Task 7. Obligation at generate + world limit: Task 8.
Advisory LSP half: Task 9. Mint preamble: Task 10. Conformance cases from the
spec's list: claim parsing (Task 2), place derivation (Task 2), exact comparison
(Task 2), quote-preserving fill — covered by Task 2's stdin/stdout test using
`{"a":1}` through `parseValue`, and end-to-end by Task 11's `logscan` witness.
Milestone 3: Task 11. Reserved-not-built names (`export.*`,
`${program.<instance>.<path>}`): no task, deliberately — the spec reserves them
in prose only.

**Type consistency.** `Claim`/`ClaimPlace` defined in Task 2 and used with the
same field names in Tasks 3, 4, 8. `claimsFile :: [Claim] -> Maybe Text`
consistent between Tasks 4 and 6. `flakeText`'s new arity fixed in Task 5 and
used in Task 6. `isGroundExpect` replaces `isArtifactExpect` in Task 7, with the
rename of every call site named explicitly.

**Known soft spots, called out rather than hidden.** Task 4's `judgeFile` is
described as a note plus a finishing instruction rather than final code, because
the here-doc nesting is easier to get right against a compiler than to
transcribe; Task 9's assertions are written against helpers the engineer must
read first (`Lsp/Derive.hs`'s diagnostic constructor); Task 6's `claimGate`
reuses `expectGate`'s temp-dir staging, which the engineer must read before
writing. Each says so at the step.
