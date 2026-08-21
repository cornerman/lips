# Mint Stats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every `lips generate` run records what it cost (wall time per phase,
model turns, tool-call counts, token usage when pi reports it) in an unsealed
file beside the sealed record, so the growth-mint work has a measured baseline
instead of a hoped-for one.

**Architecture:** Three pure pieces plus one wiring task. `Lips.Cli.Output`
already times every phase and discards the numbers, so it grows a log of
finished phases beside the live line it already owns. `Lips.Generate.PiJson`
already parses pi's `agent_end` event, so it grows three more readings of the
same event (turns, tool counts, usage). A new `Lips.Generate.Stats` holds the
record type and its renderer, pure and unit-tested. `kernel/app/Main.hs` writes
the file at the end of `generate`, on the refused path as well as the accepted
one, at a path owned by `Lips.Identity`.

**Tech Stack:** Haskell (GHC in the flake dev shell), hspec + QuickCheck in one
suite file `kernel/test/Spec.hs`, aeson for pi's JSONL, no new dependencies.
There is NO cabal file: `flake.nix` compiles with `ghc -Wall -isrc -iapp` (app)
and `-isrc -itest` (suite), so a new module under `kernel/src/` is picked up by
its path alone and no module list needs editing.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-20-mint-feedback-cycle-design.md` (errand 1).
- **Nothing here may enter `.generation`.** That record's bytes hash to `genId`
  and every minted line is stamped with it (invariant 6); a duration inside it
  would make two identical mints produce different ids.
- The suite and app stay `-Wall` clean. Fast loop: `just test`.
- No new dependency. `Lips/Kernel/**` stays base+containers+text; the new module
  is `Lips/Generate/Stats.hs` (shell tier), text only.
- Paths are known in exactly one place: `Lips.Identity`. No other module spells
  a language-folder path.
- Comments say WHY, about the current code only. Commits are single-line.
- Flakes see only git-tracked files: `git add` before any `nix run`.

---

### Task 1: The Phase Log

`Lips.Cli.Output.step` measures each phase's duration for the live line and
throws it away. Give it a log the stats writer can read afterwards.

**Files:**
- Modify: `kernel/src/Lips/Cli/Output.hs` (exports at lines 19-37; `finish` around line 160)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `data Phase = Phase { phLabel :: Text, phSecs :: Double, phOk :: Bool }`
  (Eq, Show) and `phaseLog :: IO [Phase]`, in chronological order.
- Consumes: nothing.

- [ ] **Step 1: Write the failing test**

Put it next to the other `Lips.Cli.Output` tests in `kernel/test/Spec.hs`
(search for `describe "one voice"` or `runningText`; add a new `describe` after
the last Output test). Import `Phase (..)`, `phaseLog`, `step` from
`Lips.Cli.Output`.

```haskell
  describe "the phase log (Lips.Cli.Output.phaseLog)" $ do
    it "records every finished phase in order, with its verdict" $ do
      _ <- step "first" (pure (1 :: Int))
      _ <- (step "second" (throwIO (userError "boom")) :: IO Int)
             `catch` \(_ :: SomeException) -> pure 0
      ps <- phaseLog
      map phLabel ps `shouldBe` ["first", "second"]
      map phOk ps `shouldBe` [True, False]
      all ((>= 0) . phSecs) ps `shouldBe` True
```

`throwIO`, `catch` and `SomeException` come from `Control.Exception`; check
whether `kernel/test/Spec.hs` already imports them and add only what is missing.
This test writes to stderr, which is normal for this suite's Output tests.

- [ ] **Step 2: Run it and watch it fail**

Run: `just test`
Expected: compile error, `Phase`/`phaseLog` not in scope.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Cli/Output.hs`, add to the export list (in the "Live
progress" group): `Phase (..)`, `phaseLog`. Then:

```haskell
-- | One finished phase: what it was called, how long it took, whether it held.
-- The stats a mint records are read from this log (see 'Lips.Generate.Stats');
-- the live line consumed the same numbers and dropped them, so measuring a mint
-- meant nothing in lips knew where its minutes went.
data Phase = Phase
  { phLabel :: Text
  , phSecs  :: Double
  , phOk    :: Bool
  } deriving (Eq, Show)

-- | Every phase that has finished, oldest first. Module-level state for the
-- same reason 'liveRef' is: a process runs one verb, so its phase history is a
-- singleton, and threading an accumulator through every gate in @Main.hs@ would
-- model it as if there could be several.
phasesRef :: MVar [Phase]
phasesRef = unsafePerformIO (newMVar [])
{-# NOINLINE phasesRef #-}

phaseLog :: IO [Phase]
phaseLog = reverse <$> readMVar phasesRef
```

In `finish`, inside the `Just l ->` branch, after `secs` is bound and before or
after the `emit`, append the entry (kept newest-first internally, reversed by
the reader):

```haskell
      modifyMVar_ phasesRef (pure . (Phase (lvLabel l) secs ok :))
```

`finish` is the single place a phase ends (both `step`'s success and failure
paths and `die` go through it), so the log cannot miss one.

- [ ] **Step 4: Run the tests**

Run: `just test`
Expected: PASS, `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Cli/Output.hs kernel/test/Spec.hs
git commit -m "output: keep the duration of every finished phase"
```

---

### Task 2: Turns, Tool Calls and Token Usage out of pi's Stream

**Files:**
- Modify: `kernel/src/Lips/Generate/PiJson.hs` (`PiReply` record and `parsePiReply`, around lines 20-145)
- Test: `kernel/test/Spec.hs` (existing pi-stream tests are around lines 5238-5290)

**Interfaces:**
- Produces:
  ```haskell
  data Usage = Usage { usInput, usOutput, usCacheRead, usCacheWrite :: Integer }
    deriving (Eq, Show)
  ```
  and three new `PiReply` fields: `prTurns :: Int`, `prTools :: [(Text, Int)]`
  (tool name with call count, sorted by name), `prUsage :: Maybe Usage`
  (`Nothing` when the stream reports none).
- Consumes: nothing.

**Note for the implementer:** the one existing test constructs `PiReply` positionally
(`parsePiReply "" \`shouldBe\` PiReply "" "" ""` around line 5247). It must gain
the new fields: `PiReply "" "" "" 0 [] Nothing` — in the field order declared in
the record.

- [ ] **Step 1: Write the failing test**

Add to `kernel/test/Spec.hs`, in the existing `describe` for the pi stream:

```haskell
    it "counts assistant turns and tool calls, and totals usage" $ do
      let s = T.concat
            [ "{\"type\":\"agent_end\",\"messages\":["
            , "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"go\"}]},"
            , "{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"name\":\"query_options\",\"arguments\":{\"query\":\"a\"}}],\"usage\":{\"input\":10,\"output\":2,\"cacheRead\":1,\"cacheWrite\":0}},"
            , "{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"name\":\"query_options\",\"arguments\":{\"query\":\"b\"}},{\"type\":\"toolCall\",\"name\":\"check_draft\",\"arguments\":{}}],\"usage\":{\"input\":20,\"output\":3,\"cacheRead\":0,\"cacheWrite\":5}},"
            , "{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"0.9 p1 pattern x => fact a \\\"x\\\"\"}]}"
            , "]}" ]
          r = parsePiReply s
      prTurns r `shouldBe` 3
      prTools r `shouldBe` [("check_draft", 1), ("query_options", 2)]
      prUsage r `shouldBe` Just (Usage 30 5 1 5)

    it "reports no usage when the stream carries none" $
      prUsage (parsePiReply
        "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}")
        `shouldBe` Nothing
```

Add `Usage (..)` to the `Lips.Generate.PiJson` import line (currently line 64 of
`Spec.hs`).

- [ ] **Step 2: Run it and watch it fail**

Run: `just test`
Expected: compile error, `prTurns`/`Usage` not in scope.

- [ ] **Step 3: Implement**

In `kernel/src/Lips/Generate/PiJson.hs`, export `Usage (..)` beside
`PiReply (..)`, extend the record with the three fields, and read them from the
same authoritative `agent_end` event the reply comes from:

```haskell
-- | What a mint cost, as pi's own accounting reports it. Read rather than
-- estimated: a token count lips computed itself would be a second opinion about
-- somebody else's billing.
data Usage = Usage
  { usInput      :: Integer
  , usOutput     :: Integer
  , usCacheRead  :: Integer
  , usCacheWrite :: Integer
  } deriving (Eq, Show)

-- | Assistant messages of the terminal event: one per model turn. Counted from
-- @agent_end@ rather than from the @turn_start@ events, so every number in the
-- stats comes from the one message list that is authoritative and complete.
turnsFrom :: Value -> Maybe Int
turnsFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (length [ () | Object m <- toList msgs
                        , KM.lookup "role" m == Just (String "assistant") ])
turnsFrom _ = Nothing

-- | How often the mint called each tool, by name, sorted so two runs compare
-- line by line. The @check_draft@ count is the interesting one: it says whether
-- a mint's turns went into drafting or into thinking.
toolsFrom :: Value -> Maybe [(Text, Int)]
toolsFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (M.toAscList (M.fromListWith (+) [ (n, 1 :: Int) | n <- names msgs ]))
  where
    names msgs =
      [ n
      | Object m <- toList msgs
      , KM.lookup "role" m == Just (String "assistant")
      , Just (Array content) <- [KM.lookup "content" m]
      , Object c <- toList content
      , KM.lookup "type" c == Just (String "toolCall")
      , Just (String n) <- [KM.lookup "name" c] ]
toolsFrom _ = Nothing

-- | The run's token usage: the per-message figures summed. 'Nothing' when no
-- message carries any, which is stated rather than guessed -- a zero would read
-- as a free mint.
usageFrom :: Value -> Maybe (Maybe Usage)
usageFrom (Object o)
  | KM.lookup "type" o == Just (String "agent_end")
  , Just (Array msgs) <- KM.lookup "messages" o =
      Just (case [ u | Object m <- toList msgs
                     , Just u <- [usageOf (KM.lookup "usage" m)] ] of
              []  -> Nothing
              us  -> Just (foldr1 plus us))
  where
    plus a b = Usage (usInput a + usInput b) (usOutput a + usOutput b)
                     (usCacheRead a + usCacheRead b) (usCacheWrite a + usCacheWrite b)
usageFrom _ = Nothing

-- | One message's usage object. Every field is optional and defaults to zero:
-- pi's shape is somebody else's, so a missing field must not lose the fields
-- that are there.
usageOf :: Maybe Value -> Maybe Usage
usageOf (Just (Object u)) =
  Just (Usage (num "input") (num "output") (num "cacheRead") (num "cacheWrite"))
  where
    num k = case KM.lookup k u of
      Just (Number n) -> truncate n
      _               -> 0
usageOf _ = Nothing
```

Wire them into `parsePiReply`:

```haskell
    , prTurns      = maybe 0 id (asum (map turnsFrom events))
    , prTools      = maybe [] id (asum (map toolsFrom events))
    , prUsage      = maybe Nothing id (asum (map usageFrom events))
```

Imports needed: `Data.Aeson (Number)` pattern comes from the existing
`Data.Aeson` import (`Value (..)` already brings `Number`); add
`qualified Data.Map.Strict as M` (containers, already a dependency).

- [ ] **Step 4: Run the tests**

Run: `just test`
Expected: PASS (including the amended positional `PiReply` test), `-Wall` clean.

- [ ] **Step 5: Verify pi really emits `usage` (this decides whether the token
      lines are ever populated)**

Run, in a shell where `pi` is on PATH (the user's harness, NOT the dev shell):

```bash
echo hi | pi -p -nt --no-session --mode json --model anthropic/claude-sonnet-5 \
  | tr ',' '\n' | grep -i -m5 'usage\|input\|output'
```

Write what you saw into the commit message body: either the field names pi uses
(and adjust `usageOf`'s keys to match, exactly) or "pi reports no usage on
agent_end", in which case leave the code as it is — `prUsage` correctly answers
`Nothing` and the stats file will say so in words.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Generate/PiJson.hs kernel/test/Spec.hs
git commit -m "pijson: read turns, tool counts and token usage from agent_end"
```

---

### Task 3: The Stats File, Rendered

**Files:**
- Create: `kernel/src/Lips/Generate/Stats.hs` (no build-file edit: modules are found by `-isrc`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Cli.Output.Phase (..)`, `Lips.Generate.PiJson.Usage (..)`.
- Produces:
  ```haskell
  data MintStats = MintStats
    { mtVerdict  :: Text            -- "accepted", or "refused at <phase>"
    , mtModel    :: Text
    , mtThinking :: Text
    , mtWall     :: Double          -- whole verb, seconds
    , mtPhases   :: [Phase]
    , mtTurns    :: Int
    , mtTools    :: [(Text, Int)]
    , mtUsage    :: Maybe Usage
    } deriving (Eq, Show)

  verdictOf   :: [Phase] -> Text
  renderStats :: MintStats -> Text
  ```

- [ ] **Step 1: Write the failing test**

```haskell
  describe "mint stats (Lips.Generate.Stats)" $ do
    it "renders one key-per-line record a human and a grep can both read" $
      renderStats MintStats
        { mtVerdict  = "accepted"
        , mtModel    = "anthropic/claude-opus-5"
        , mtThinking = "medium"
        , mtWall     = 257.25
        , mtPhases   = [Phase "schema" 12.5 True, Phase "mint nixos" 231.0 True]
        , mtTurns    = 7
        , mtTools    = [("check_draft", 3), ("query_options", 4)]
        , mtUsage    = Just (Usage 41233 5120 0 12)
        } `shouldBe` T.unlines
          [ "format: 1"
          , "verdict: accepted"
          , "model: anthropic/claude-opus-5"
          , "thinking: medium"
          , "wall: 257.2"
          , "phase schema: 12.5"
          , "phase mint nixos: 231.0"
          , "turns: 7"
          , "tool check_draft: 3"
          , "tool query_options: 4"
          , "tokens input: 41233"
          , "tokens output: 5120"
          , "tokens cache-read: 0"
          , "tokens cache-write: 12"
          ]

    it "says in words when pi reported no usage, instead of writing zeros" $
      T.isInfixOf "tokens: not reported\n"
        (renderStats (MintStats "accepted" "m" "medium" 1.0 [] 1 [] Nothing))
        `shouldBe` True

    it "names the phase a refused mint died in" $ do
      verdictOf [Phase "schema" 1 True, Phase "mint nixos" 2 False]
        `shouldBe` "refused at mint nixos"
      verdictOf [Phase "schema" 1 True] `shouldBe` "accepted"
```

Add the import line `import Lips.Generate.Stats (MintStats (..), renderStats, verdictOf)`
to `Spec.hs`.

- [ ] **Step 2: Run it and watch it fail**

Run: `just test`
Expected: compile error, module `Lips.Generate.Stats` not found.

- [ ] **Step 3: Implement**

Create `kernel/src/Lips/Generate/Stats.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | What one mint COST, as opposed to what it was made of.
--
-- The inputs of a generation event live in @.generation@, whose bytes hash to
-- the id every minted line is stamped with (invariant 6). A duration cannot go
-- there: two identical mints would then produce different ids, and every stamp
-- would stop re-hashing. So the cost gets its own unsealed file beside the
-- record, and the split is the point -- sealed inputs in the record, observed
-- costs next to it.
--
-- It is committed like every other machine-written file in a world folder,
-- because the cost of a mint is a fact about the engine that was committed, and
-- comparing two mints is a diff.
module Lips.Generate.Stats
  ( MintStats (..)
  , verdictOf
  , renderStats
  ) where

import           Data.Text            (Text)
import qualified Data.Text            as T
import           Lips.Cli.Output      (Phase (..))
import           Lips.Generate.PiJson (Usage (..))

data MintStats = MintStats
  { mtVerdict  :: Text
  , mtModel    :: Text
  , mtThinking :: Text
  , mtWall     :: Double
  , mtPhases   :: [Phase]
  , mtTurns    :: Int
  , mtTools    :: [(Text, Int)]
  , mtUsage    :: Maybe Usage
  } deriving (Eq, Show)

-- | Accepted, or the name of the phase that failed. Derived from the phase log
-- rather than passed in, so the file cannot disagree with what the terminal
-- showed.
verdictOf :: [Phase] -> Text
verdictOf ps = case [ phLabel p | p <- ps, not (phOk p) ] of
  (l : _) -> "refused at " <> l
  []      -> "accepted"

-- | One fact per line, @key: value@, the same shape @.generation@ uses, so the
-- two read alike and either can be grepped without a parser.
renderStats :: MintStats -> Text
renderStats s = T.unlines $
  [ "format: 1"
  , "verdict: " <> mtVerdict s
  , "model: " <> mtModel s
  , "thinking: " <> mtThinking s
  , "wall: " <> secs (mtWall s) ]
  ++ [ "phase " <> phLabel p <> ": " <> secs (phSecs p) | p <- mtPhases s ]
  ++ [ "turns: " <> T.pack (show (mtTurns s)) ]
  ++ [ "tool " <> n <> ": " <> T.pack (show c) | (n, c) <- mtTools s ]
  ++ tokens (mtUsage s)
  where
    -- One decimal: a mint is minutes, so tenths of a second are the finest
    -- figure that means anything, and a fixed shape keeps two files diffable.
    secs x = T.pack (show (fromIntegral (round (x * 10) :: Integer) / 10 :: Double))
    -- Absence is stated, never rendered as zero: a zero would read as a mint
    -- that cost no tokens.
    tokens Nothing  = [ "tokens: not reported" ]
    tokens (Just u) =
      [ "tokens input: " <> T.pack (show (usInput u))
      , "tokens output: " <> T.pack (show (usOutput u))
      , "tokens cache-read: " <> T.pack (show (usCacheRead u))
      , "tokens cache-write: " <> T.pack (show (usCacheWrite u)) ]
```


- [ ] **Step 4: Run the tests**

Run: `just test`
Expected: PASS. If the `wall: 257.2` expectation fails on rounding, fix the
TEST to the value `secs` actually produces for 257.25 (banker's rounding is
GHC's `round`), not the renderer: a fixed shape is all that matters.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Generate/Stats.hs kernel/test/Spec.hs
git commit -m "stats: what a mint cost, rendered as an unsealed record"
```

---

### Task 4: Where the Stats File Lives

**Files:**
- Modify: `kernel/src/Lips/Identity.hs` (exports around lines 48-60; the path helpers alongside `expectPathIn`/`gapPathIn`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  timingPathIn     :: FilePath -> Text -> FilePath -> FilePath
  languageTimingPath :: FilePath -> FilePath -> FilePath
  ```
  Same argument shapes as the existing `gapPathIn` / `languageGapPathIn`; read
  those two first and mirror them exactly.

- [ ] **Step 1: Write the failing test**

Add beside the existing `Lips.Identity` path tests (grep `gapPathIn` in
`Spec.hs` to find them):

```haskell
    it "puts a mint's timing beside the record it belongs to" $ do
      timingPathIn "examples/backup" "nixos" "ledger.backup.lips"
        `shouldBe` "examples/backup/nixos/backup.timing"
      languageTimingPath "examples/backup" "ledger.backup.lips"
        `shouldBe` "examples/backup/backup.timing"
```

Confirm the expected strings against what `gapPathIn`/`expectPathIn` produce for
the same inputs (run them in the test first if unsure) and match that
convention, including whether the basename is the LANGUAGE (it is: minted files
keep the language prefix, `Lips.Identity`'s header comment).

- [ ] **Step 2: Run it and watch it fail**

Run: `just test`
Expected: compile error, `timingPathIn` not in scope.

- [ ] **Step 3: Implement**

```haskell
-- | Where a mint's cost is recorded: beside the sealed record in the world's
-- own folder. A run covering SEVERAL worlds records one cost at the language
-- level instead, because the call is the event -- the same rule
-- 'gapPathIn'\/'languageGapPathIn' already follow for a refusal.
timingPathIn :: FilePath -> Text -> FilePath -> FilePath
timingPathIn dir world = langLevelIn (worldDirIn dir world) "timing"

languageTimingPath :: FilePath -> FilePath -> FilePath
languageTimingPath dir = langLevelIn dir "timing"
```

That is `gapPathIn`'s own shape (line 238) with a different extension:
`langLevelIn dir ext file = dir </> languageName file <.> ext` is the one place
that spells a language basename, so nothing new is introduced. Add both names to
the export list beside `gapPathIn` / `languageGapPathIn`.

- [ ] **Step 4: Run the tests**

Run: `just test`
Expected: PASS, `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Identity.hs kernel/test/Spec.hs
git commit -m "identity: the path of a mint's timing record"
```

---

### Task 5: Generate Writes It, on Both Paths

**Files:**
- Modify: `kernel/app/Main.hs` (`generate`, from line 873; the mint call at line 938; the refusal `die` at ~line 975)
- Modify: `DESIGN.md` (§13 milestone ledger: a new entry at the top of the section)
- Modify: `TODO.md` (mark errand 1 of the growth-mint item done, leaving errands 2 and 3)

**Interfaces:**
- Consumes: `Lips.Cli.Output.phaseLog`, `Lips.Generate.Stats.{MintStats(..), renderStats, verdictOf}`,
  `Lips.Generate.PiJson.{prTurns, prTools, prUsage}`,
  `Lips.Identity.{timingPathIn, languageTimingPath}`.
- Produces: a written `<language>/<world>/<lang>.timing` (or the language-level
  file for a multi-world run).

**Design decisions already made — do not re-litigate:**
1. Written on the REFUSED path too: a refused mint costs a whole round, which is
   the number the growth-mint work most wants. `die` throws `ExitFailure`, so the
   write goes in an exception handler around the body, and `verdictOf` reads the
   verdict off the phase log.
2. NOT written when the mint was refused before its world folder exists: a lone
   `.timing` in an otherwise empty directory is surprising. Condition: write if
   the target directory already exists, or if the verdict is "accepted".
3. `callPi` currently returns `(Text, Text, Text)`. It must return the counts as
   well; widen it to return the whole `PiReply` (it already builds one) and let
   the caller destructure. Keep the existing three bindings at the call site so
   the diff stays small.

- [ ] **Step 1: Widen `callPi` to hand back what it already parsed**

At `kernel/app/Main.hs:1367`, change the signature's result to `IO PiReply` and
return the parsed value instead of the tuple (the `ExitSuccess` branch already
destructures a `PiReply`; return it whole). At the call site (line ~938) bind:

```haskell
  piReply <- step (...) $ callPi ...
  let reply      = prReply piReply
      model      = prModel piReply
      transcript = prTranscript piReply
```

Run: `just test`
Expected: PASS (`-Wall` clean; no test constructs the tuple).

- [ ] **Step 2: Write the stats, wrapping the body of `generate`**

Near the top of `generate` (before the `grounds <- ...` block), take the clock:

```haskell
  t0 <- getPOSIXTime
```

Hold the model, thinking level and counts in an `IORef` that starts as the
pre-mint truth and is filled once the model answered, so a mint that dies BEFORE
the model still records its wall time and phases:

```haskell
  -- The mint's own numbers are only known after it answered; a run refused
  -- before that still records its phases, which is what says where the minutes
  -- went when a schema build is the expensive part.
  costRef <- newIORef (Nothing :: Maybe PiReply)
```

Set it right after the mint call: `writeIORef costRef (Just piReply)`.

Wrap the whole remaining body in a handler that writes the file either way. The
verb's existing body becomes `body`; add:

```haskell
  let writeStats = do
        ps <- phaseLog
        mpi <- readIORef costRef
        now <- getPOSIXTime
        let stats = MintStats
              { mtVerdict  = verdictOf ps
              , mtModel    = maybe "" prModel mpi
              , mtThinking = T.pack thinking
              , mtWall     = realToFrac (now - t0)
              , mtPhases   = ps
              , mtTurns    = maybe 0 prTurns mpi
              , mtTools    = maybe [] prTools mpi
              , mtUsage    = mpi >>= prUsage
              }
            path = case wnames of
                     [w] -> timingPathIn dir w rep
                     _   -> languageTimingPath dir rep
        there <- doesDirectoryExist (takeDirectory path)
        -- A refusal before the folder exists leaves no lone timing file behind;
        -- an accepted mint has just created the folder, so it always writes.
        when (there || mtVerdict stats == "accepted") $ do
          createDirectoryIfMissing True (takeDirectory path)
          TIO.writeFile path (renderStats stats)
          note ("cost recorded in " <> T.pack path)
  body `onException` writeStats
  writeStats
```

`onException` comes from `Control.Exception` (check the existing import list),
`getPOSIXTime` from `Data.Time.Clock.POSIX`, `newIORef`/`readIORef`/`writeIORef`
from `Data.IORef`. Structure the code however reads best in that function — what
matters is: written exactly once on each path, and never swallowing the original
exception.

Run: `just test`
Expected: PASS, `-Wall` clean.

- [ ] **Step 3: Verify against a real mint (the baseline measurement)**

This is the one step that spends a model call. `pi` is NOT in the dev shell, so
run it from the user's own shell.

```bash
git add -A && nix run . -- generate examples/greet.lips
cat examples/greet/home-manager/greet.timing
```

Expected: a file whose `verdict: accepted`, whose `wall:` is within a few
seconds of what the terminal showed, whose phase lines match the `✓` lines that
scrolled past, and whose `turns:` is at least 1. Then check the refused path
without paying for it, by pointing the mint at a program whose schema cannot
resolve (e.g. `nix run . -- generate --target nosuchworld examples/greet.lips`):
expected, no `.timing` write for a nonexistent world folder and the ordinary
refusal report.

If `greet`'s engine changed in the process, `git checkout` the engine files: this
step measures, it does not re-mint the corpus.

- [ ] **Step 4: Record what was measured**

Add a `DESIGN.md` §13 entry (top of the section, matching the style of its
neighbours: what the defect was, what landed, what was measured, what is
verified) naming the actual numbers from Step 3 — wall time, turns,
`check_draft` count, and whether pi reported tokens. This is the "before" figure
the growth mint will be judged against, so it must be a number, not a claim.

Then strike errand 1 from the growth-mint item in `TODO.md`, leaving errands 2
and 3 and a one-line pointer to the DESIGN entry.

- [ ] **Step 5: Commit**

```bash
git add kernel/app/Main.hs DESIGN.md TODO.md
git commit -m "generate: record what a mint cost beside its record"
```

- [ ] **Step 6: Full verification before merge**

```bash
just test
just check-expect
just ci        # needs KVM
```

Expected: all green. `just ci` includes `nix flake check` and the draft-door
wordings.

---

## Self-Review

**Spec coverage (errand 1 of the design doc):** per-phase and total wall time —
Tasks 1, 3, 5. Turn count and tool-call counts — Task 2. Token usage, with
absence stated rather than guessed — Tasks 2, 3, plus the Step 5 check in Task 2
that settles whether pi reports it at all. Verdict and the "refused at" case —
Task 3 (`verdictOf`), Task 5. Committed file beside the sealed record, path owned
by `Lips.Identity` — Task 4. `.generation` untouched, so `genId` stays
reproducible — stated as a global constraint and honoured by Task 5 (nothing is
added to `record`). The `basis:` field is deliberately NOT here: it is an input
of the patch mint, and belongs to errand 2.

**Type consistency:** `Phase`/`phLabel`/`phSecs`/`phOk` (Task 1) are consumed
under those names in Tasks 3 and 5. `Usage`/`usInput`/`usOutput`/`usCacheRead`/
`usCacheWrite` and `prTurns`/`prTools`/`prUsage` (Task 2) are consumed under
those names in Tasks 3 and 5. `MintStats` fields `mt*` (Task 3) are constructed
once, in Task 5. `timingPathIn`/`languageTimingPath` (Task 4) are called in
Task 5 with `(dir, world, rep)` and `(dir, rep)`, matching the signatures.

**Known soft spots, flagged rather than hidden:** the exact key names in pi's
`usage` object are unverified (Task 2 Step 5 verifies them against a live stream
and says what to do either way), and `Lips.Identity`'s helper for a language
basename is to be read from `gapPathIn` and reused rather than re-spelled
(Task 4 Step 3).
