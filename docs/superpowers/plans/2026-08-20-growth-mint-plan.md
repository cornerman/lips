# The Growth Mint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `generate` against a language that already has a committed engine asks
the model for a PATCH (a few lines keyed by id) instead of a whole engine, so
adding one sentence shape costs a short mint instead of a full one.

**Architecture:** Everything downstream of the reply stays untouched. Two pure
text merges do the work: the committed engine is rendered back into reply lines
and merged with the patch (patch wins by id) BEFORE `parseEngineCandidates`, so
gates, rendering and writing see a complete engine exactly as today; and at write
time the rendered engine is merged against the committed bytes so a line the
patch did not touch keeps its own text and its own `@gen:` stamp. The draft tool
merges identically, so what the model checks is what the gate will judge.

**Tech Stack:** Haskell, hspec in `kernel/test/Spec.hs`, no new dependencies.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-20-mint-feedback-cycle-design.md`
  (errand 2). Errand 1 has landed (DESIGN §13, "A mint now says what it cost"),
  and its baseline numbers are what this work is measured against: `greet` fresh
  = 326s / 6 turns / 26,598 output tokens / $0.43 on sonnet-5.
- Deletion has NO patch form. `--fresh` is how a line goes away.
- Append-only stays where it is: `appendOnlyViolations` guards the shared grammar
  against a run that does not cover every committed world. A patch is refused
  there exactly as a rewrite is today.
- Invariant 6: `basis` is an INPUT of the event, so it enters `.generation` and
  therefore `genId`. Timing figures never do (that is errand 1's file).
- Invariant 4: generated output is never hand-edited. A patch that cannot express
  a change fails loud naming `--fresh`.
- `-Wall` clean, `just test` between steps, single-line commits, no new deps.
- Paths only through `Lips.Identity`. Flakes see only tracked files: `git add`
  before `nix run`.

---

### Task 1: The Two Pure Merges

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs` (beside `mergeGrammar`, line ~320)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces:
  ```haskell
  replyLinesOf  :: Maybe Text -> Text -> Text   -- world tag, engine file text
  mergeReply    :: Text -> Text -> Text         -- inherited lines, patch
  touchedIds    :: Text -> [Text]               -- ids a patch mentions
  mergeTouched  :: [Text] -> Text -> Text -> Text -- touched, committed, rendered
  ```
- Consumes: `Lips.Kernel.Reader.readDecision`, `Lips.Kernel.Decision` accessors.

**Why these shapes:** a committed engine line is
`r1 meta engine.rule.r1 stated "match fact x => y \"z\"" @gen:abc`, and the
assertion inside the quotes IS the reply line's tail, so `replyLinesOf` turns a
committed engine back into the reply format the one parser already reads. No
second parser, no second grammar.

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "the growth mint's merges (Lips.Generate.Minting)" $ do
    let committed = T.unlines
          [ "p1 meta lang.pattern.p1 stated \"install <name> => fact cmd.<name> \\\"<name>\\\"\" @gen:aaa"
          , "r1 meta engine.rule.r1 stated \"match fact cmd.<name> => environment.systemPackages \\\"[ <value:pkg> ]\\\"\" @gen:aaa"
          ]
    it "renders a committed engine back into reply lines the mint can read" $ do
      let ls = T.lines (replyLinesOf Nothing committed)
      length ls `shouldBe` 2
      head ls `shouldBe` "1.0 p1 install <name> => fact cmd.<name> \"<name>\""
    it "tags every line when the run writes for several worlds" $
      T.isInfixOf "1.0 r1 @nixos match fact" (replyLinesOf (Just "nixos") committed)
        `shouldBe` True
    it "a patch replaces by id, adds new ids and leaves the rest" $ do
      let patch = T.unlines
            [ "0.9 r1 match fact cmd.<name> => home.packages \"[ <value:pkg> ]\""
            , "0.9 p2 pattern quietly => concept quiet \"quietly\"" ]
          merged = T.lines (mergeReply (replyLinesOf Nothing committed) patch)
      length merged `shouldBe` 3
      merged `shouldSatisfy` any (T.isInfixOf "home.packages")
      merged `shouldSatisfy` any (T.isInfixOf "1.0 p1 install")
      merged `shouldSatisfy` all (not . T.isInfixOf "environment.systemPackages")
    it "reads the ids a patch touched, so writing can keep the other bytes" $
      touchedIds (T.unlines [ "0.9 r1 match fact a => b \"c\"", "0.9 d1 report x" ])
        `shouldBe` ["r1", "d1"]
    it "writing keeps a committed line verbatim unless the patch touched it" $ do
      let rendered = T.unlines
            [ "p1 meta lang.pattern.p1 stated \"install <name> => fact cmd.<name> \\\"<name>\\\"\" @gen:bbb"
            , "r1 meta engine.rule.r1 stated \"match fact cmd.<name> => home.packages \\\"[ <value:pkg> ]\\\"\" @gen:bbb"
            ]
          out = T.lines (mergeTouched ["r1"] committed rendered)
      -- p1 was not touched, so its own stamp survives; r1 is the patch's.
      out `shouldSatisfy` any (T.isInfixOf "p1 meta lang.pattern.p1 stated \"install <name>")
      out `shouldSatisfy` any (T.isInfixOf "@gen:aaa")
      out `shouldSatisfy` any (T.isInfixOf "home.packages")
      out `shouldSatisfy` any (T.isInfixOf "@gen:bbb")
```

- [ ] **Step 2: Run and watch them fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/gm -o /tmp/gm-spec` (inside `nix develop -c bash -c '...'`)
Expected: not in scope errors for the four names.

- [ ] **Step 3: Implement**

```haskell
-- | A committed engine, rendered back into the reply format a mint writes.
--
-- This is what makes a PATCH cheap without a second grammar: an engine line
-- carries the reply line's own text as its assertion, so handing the model (and
-- the merge below) the committed engine costs a re-quote, not a translation.
-- Confidence 1.0, because a committed line already passed every gate; the world
-- tag is added only when the run writes for several worlds, so a single-world
-- reply stays byte-identical to what mints wrote before tags existed.
replyLinesOf :: Maybe Text -> Text -> Text
replyLinesOf tag src = T.unlines
  [ T.unwords ([ "1.0", unId (dId d) ] ++ maybe [] (\w -> ["@" <> w]) tag
                 ++ [ unAssertion (dAssertion d) ])
  | l <- T.lines src, Right d <- [readDecision (T.strip l)] ]

-- | The engine a patch means: every inherited line, with the ones the patch
-- restates replaced and the ones it adds appended. An id the patch does not
-- mention is inherited verbatim, which is the whole point -- the model pays for
-- what it changes, not for what it keeps.
mergeReply :: Text -> Text -> Text
mergeReply inheritedLines patch = T.unlines $
  [ l | l <- T.lines inheritedLines, idOf l `notElem` touched ]
  ++ T.lines patch
  where touched = touchedIds patch

-- | The ids a patch mentions: token 2 of every line that has one (token 1 is the
-- confidence). Blank and continuation lines carry none.
touchedIds :: Text -> [Text]
touchedIds t = [ i | l <- T.lines t, (_ : i : _) <- [T.words l] ]

-- | What to WRITE: the rendered engine, except that a line the patch never
-- touched keeps its committed bytes -- and therefore its own @\@gen:@ stamp,
-- since that line was minted by the run whose record still hashes to it
-- (invariant 6). The same move 'mergeGrammar' makes for a second world's
-- grammar, generalized to any engine file and to replacement.
mergeTouched :: [Text] -> Text -> Text -> Text
mergeTouched touched committed rendered = T.unlines
  [ fromMaybe l (keep (idOf l)) | l <- T.lines rendered ]
  where
    keep i | i `elem` touched = Nothing
           | otherwise = lookup i [ (idOf c, c) | c <- T.lines committed ]

idOf :: Text -> Text
idOf l = case T.words l of
  (w : _) -> w
  []      -> ""
```

Note the asymmetry, and keep it: `replyLinesOf`'s id is token 2 (after the
confidence), an engine file's id is token 1. Use a local helper for each rather
than one that guesses.

Imports to add: `Lips.Kernel.Reader (readDecision)`, the `Decision` accessors
already in scope via `Lips.Kernel.Decision`, and `Data.Maybe (fromMaybe)`.

- [ ] **Step 4: Run the tests**

Expected: PASS, `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Generate/Minting.hs kernel/test/Spec.hs
git commit -m "minting: a committed engine reads back as reply lines a patch merges into"
```

---

### Task 2: `--fresh`, and the Basis in the Record

**Files:**
- Modify: `kernel/src/Lips/Cli.hs` (`GenerateOpts`, its parser)
- Modify: `kernel/src/Lips/Generate/Record.hs` (`record`)
- Modify: `kernel/app/Main.hs` (dispatch at line ~151, `generate`'s signature)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `goFresh :: Bool` in `GenerateOpts`; `record` gains a `Text`
  parameter `basis`, rendered as one line after `model:`.
- Consumes: nothing new.

**Decisions:** the value is `fresh` or `inherited <genid>` where `<genid>` is the
id of the record the inherited engine was stamped from (read from the committed
`.generation`); a language folder with no record inherits nothing and records
`fresh`. `--fresh` is a flag on `generate`, not a new verb, and the CHEAP path is
the default, since growth is the common act.

- [ ] **Step 1: Write the failing test**

```haskell
    it "the record names the basis the mint grew from" $ do
      let r = record "m" [("nixos", "h", "p")] "medium" 0.7 "inherited aaa" "sys" "prog" "t" "reply"
      T.lines r !! 2 `shouldBe` "basis: inherited aaa"
```

Find the existing `record` tests (grep `"format: 1"` in `Spec.hs`) and place it
beside them; every existing call to `record` in the suite gains the new argument.

- [ ] **Step 2: Run and watch it fail** (arity error at the call sites).

- [ ] **Step 3: Implement**

In `Record.hs`, add the parameter and the line:

```haskell
record :: Text -> [(Text, Text, Text)] -> Text -> Double -> Text -> Text -> Text -> Text -> Text -> Text
record model worlds thinking confidence basis sysPrompt program transcript reply = T.unlines $
  [ "format: 1"
  , "model: " <> model
  -- What this mint GREW FROM: an inherited engine is an input of the event, so
  -- it is pinned like the schema and the world (invariant 6). Without it, two
  -- mints of the same reply -- one from scratch, one appending -- would record
  -- the same event.
  , "basis: " <> basis ]
  ++ ...
```

In `Cli.hs` add `goFresh` with

```haskell
  <*> switch (long "fresh" <> help "rewrite the engine from scratch instead of patching the committed one")
```

placed in the same order as the field, and thread it through `generate`'s
signature in `Main.hs` (one more `Bool` beside `verbose`).

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/src/Lips/Generate/Record.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "generate: --fresh, and the basis a mint grew from enters the record"
```

---

### Task 3: The Prompt Section

**Files:**
- Create: `kernel/assets/mint/patch.md` — check where the other assets live
  (`assets/mint/*.md` at the repo root, embedded via file-embed in
  `Lips.Generate.Minting`; follow exactly how `grammar.md` is embedded and
  substituted).
- Modify: `kernel/src/Lips/Generate/Minting.hs` (`promptWithDirection`)
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `promptWithDirection` gains a `Maybe Text` for the inherited ENGINE
  (beside the existing inherited grammar), substituted into `patchDoc`'s
  `{{ENGINE}}` placeholder.

- [ ] **Step 1: Write the failing test**

```haskell
    it "a patch mint is told what it inherits and how to answer" $ do
      let p = promptWithDirection Nothing Nothing (Just "1.0 r1 match fact a => b \"c\"") [builtinNixos]
      p `shouldSatisfy` T.isInfixOf "1.0 r1 match fact a => b \"c\""
      p `shouldSatisfy` T.isInfixOf "id you do not mention"
    it "a fresh mint's prompt has no inherited-engine section" $
      promptWithDirection Nothing Nothing Nothing [builtinNixos]
        `shouldSatisfy` (not . T.isInfixOf "id you do not mention")
```

Use whatever the suite already uses for a world value (grep `builtinWorld` in
`Spec.hs`) rather than inventing `builtinNixos`.

- [ ] **Step 2: Run and watch it fail** (arity error).

- [ ] **Step 3: Implement**

`assets/mint/patch.md`:

```markdown
THE ENGINE YOU INHERIT (this language is already minted; you are EXTENDING it).

Below is the committed engine, in the same line format you answer in. It already
passes every gate and already serves every program in the corpus.

Answer with a PATCH, not with a whole engine:
  - a line whose id is NEW adds it,
  - a line whose id ALREADY EXISTS below replaces that line entirely,
  - an id you do not mention stays exactly as it is.
There is no way to delete a line, and you must not restate a line you are not
changing: restating costs the human money and risks changing what already holds.
Change an existing line only where the program cannot be read without it, and
say why in the report.

{{ENGINE}}
```

In `Minting.hs`, thread the new argument and substitute exactly as the direction
and grammar sections do (`section mEngine patchDoc "{{ENGINE}}"`), placing the
inherited engine BEFORE the direction, since it is what the direction steers.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/mint/patch.md kernel/src/Lips/Generate/Minting.hs kernel/test/Spec.hs
git commit -m "mint: the prompt section for a patch against a committed engine"
```

---

### Task 4: Generate Inherits, Merges and Writes

**Files:**
- Modify: `kernel/app/Main.hs` (`generate`, and `callPi`'s child environment)

**Interfaces:**
- Consumes: Task 1's merges, Task 2's `goFresh`/`basis`, Task 3's prompt slot.
- Produces: `LIPS_MINT_BASIS` in the mint's environment (the language directory
  whose engine the draft must merge with, empty when fresh).

- [ ] **Step 1: Read the committed engine and build the inherited reply**

In `generate`, after `wnames` is bound and before the prompt is built:

```haskell
  -- The engine this mint grows from: the committed grammar plus each world's
  -- rules, rendered back into reply lines. Absent under --fresh and on a first
  -- mint, and then everything below is exactly the old whole-engine path.
  basisText <- if fresh then pure Nothing else do
    g <- tryRead (grammarPathIn dir rep)
    rs <- forM wnames $ \w -> fmap ((,) w) <$> ... -- tryRead (rulesPathIn dir w rep)
    let tag = if length wnames > 1 then Just else const Nothing
    pure (case (g, [ (w, t) | Just (w, t) <- rs ]) of
            (Nothing, []) -> Nothing
            (mg, ws) -> Just (T.concat (maybe [] (\t -> [replyLinesOf Nothing t]) mg
                                          ++ [ replyLinesOf (tag w) t | (w, t) <- ws ])))
```

Write it in whatever shape reads best; what matters: the grammar's lines carry no
world tag (patterns are shared) and a world's rules carry theirs only when the
run writes for several worlds.

- [ ] **Step 2: Merge the reply, and pass the basis to the prompt and the tool**

- `prompt = promptWithDirection direction inherited basisText worlds`
- after the mint: `let reply = maybe rawReply (`mergeReply` rawReply) basisText`
  where `rawReply = prReply piReply`, and keep `touched = touchedIds rawReply`
  for the write step.
- in `callPi`'s `ours` list add `("LIPS_MINT_BASIS", maybe "" (const dir) basisText)`
  — the DIRECTORY, so the tool reads the same committed files through
  `Lips.Identity` rather than being handed text through the environment.
- the record call passes `basis`: `"fresh"` when `fresh` or nothing was
  inherited, else `"inherited " <> genid` read from the committed record via
  `governingRecord`/`genId` (grep `governingRecord` in `Main.hs`: it already
  reads the record that governs a world).

- [ ] **Step 3: Keep untouched bytes when writing**

At the write step, the grammar already merges (`mergeGrammar inherited ...`).
For each world's rules, wrap the rendered text:

```haskell
      committedRules <- tryRead (rulesPathIn dir wn rep)
      let rulesOut = maybe renderedRules (\c -> mergeTouched touched c renderedRules) committedRules
```

- [ ] **Step 4: Report what the patch did**

Beside the existing per-file notes, print one line naming the ids added and the
ids replaced (`note`), because that is the diff a human wants before an engine
changes under them.

- [ ] **Step 5: Build and run the suite**

Expected: `-Wall` clean, 899+ green.

- [ ] **Step 6: Commit**

```bash
git add kernel/app/Main.hs
git commit -m "generate: patch a committed engine by id, rewrite only with --fresh"
```

---

### Task 5: The Draft Tool Judges the Merged Engine

**Files:**
- Modify: `kernel/app/Main.hs` (`checkDraft`, line ~626)
- Test: extend `justfile`'s `test-draft` recipe with a patch case

**Interfaces:**
- Consumes: `LIPS_MINT_BASIS` (a language directory, empty when fresh),
  Task 1's `replyLinesOf`/`mergeReply`.

- [ ] **Step 1: Merge before materializing**

```haskell
  -- The draft is judged as the ENGINE it will become: a patch alone is not an
  -- engine, and judging it alone would refuse every mint that keeps a committed
  -- pattern. generate names the basis; nothing is guessed.
  basisDir <- lookupEnv "LIPS_MINT_BASIS"
  merged <- case basisDir of
    Just d | not (null d) -> do
      g <- tryRead (grammarPathIn d file)
      rs <- forM (map wName ws) $ \w -> fmap ((,) w) <$> tryRead (rulesPathIn d w file)
      pure (mergeReply (T.concat (...same shape as generate...)) reply)
    _ -> pure reply
```

Factor the "committed engine as reply lines" construction into ONE function used
by both `generate` and `checkDraft` (it is the same concept; two copies would
drift). Put it next to the merges in `Lips.Generate.Minting` with an `IO`-free
signature taking the texts, and let each caller read its own files.

- [ ] **Step 2: Extend `test-draft` with the patch case**

Append to the recipe, following its existing style (a temp language folder, then
`check --draft` over stdin):

```bash
    # A PATCH is judged as the engine it becomes: the committed pattern stays,
    # the patch's rule replaces the committed one, and the result must hold.
    export LIPS_MINT_BASIS="$tmp"
    printf 'watch 30 seconds\n' > "$tmp/one.watch.lips"
    mkdir -p "$tmp/watch/nixos"
    cat > "$tmp/watch/watch.grammar" <<'EOF'
    p1 meta lang.pattern.p1 stated "watch <secs> seconds => fact watch.interval \"<secs>\"" @gen:aaa
    EOF
    cat > "$tmp/watch/nixos/watch.rules" <<'EOF'
    r1 meta engine.rule.r1 stated "match fact watch.interval => systemd.services.w.environment.S \"<value:int>\"" @gen:aaa
    EOF
    sed -i 's/^    //' "$tmp/watch/watch.grammar" "$tmp/watch/nixos/watch.rules"
    printf '0.95 r1 match fact watch.interval => systemd.services.w.environment.T "<value:int>"\n' > "$tmp/patch.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/patch.txt" > "$tmp/out13" 2>&1 \
      || { echo "FAIL: a patch against a committed engine was refused"; cat "$tmp/out13"; exit 1; }
    grep -q "environment.T" "$tmp/out13" || true
    unset LIPS_MINT_BASIS
```

Adjust the assertions to what the verb actually prints (run it once and read the
output); the point of the case is that a reply carrying ONLY a rule is judged as
a complete engine because the committed pattern is merged in.

- [ ] **Step 3: Run it**

```bash
sed -n '/^test-draft:/,$p' justfile | tail -n +3 | sed 's/^    //' > /tmp/td.sh && bash /tmp/td.sh
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add kernel/app/Main.hs justfile
git commit -m "draft: a patch is judged as the engine it becomes"
```

---

### Task 6: Measure It, Then Record It

- [ ] **Step 1: Grow a language for real**

Pick the cheapest honest case: add one sentence shape to `examples/greet.lips`
(e.g. a second line stating something the language cannot read), then

```bash
git add -A
nix run . -- generate --model anthropic/claude-sonnet-5 examples/greet.lips
cat examples/greet/home-manager/greet.timing
```

Expected, and this is the whole point: `turns` and `tokens output` far below the
baseline (`greet` fresh was 6 turns / 26,598 output / 326s / $0.43 on the same
model), with the committed pattern absent from the reply and present in the
written engine.

- [ ] **Step 2: Verify the engine is whole and honest**

```bash
grep -c "" examples/greet/home-manager/greet.rules examples/greet/greet.grammar
grep -o "@gen:[a-f0-9]*" examples/greet/greet.grammar | sort -u
nix run . -- check examples/greet.lips
```

Expected: the untouched line still carries the OLD `@gen:` id, the patched line
the new one, and `check` green.

- [ ] **Step 3: Full verification**

```bash
just test
for p in examples/*.lips; do nix run . -- check "$p" || echo "FAIL $p"; done
bash /tmp/td.sh                      # test-draft
nix build .#checks.x86_64-linux.kernel-tests --no-link -L
```

(`nix flake check` also runs `artifact-vm`, which is red for an unrelated,
recorded reason: TODO item -2, `website`'s unit cannot boot.)

- [ ] **Step 4: Record the result**

Add a DESIGN §13 entry with BOTH numbers side by side (fresh baseline vs patch),
name what the patch reply contained, and state the accepted cost (prompt and
physics improvements no longer reach committed languages until someone runs
`--fresh`; the record's `basis:` line is what makes that visible). Strike errand
2 from TODO, leaving errand 3.

- [ ] **Step 5: Commit and merge**

```bash
git add -A && git commit -m "measured: a growth mint against a committed engine"
```
Then rebase onto main and fast-forward merge (no merge commits).

## Self-Review

**Spec coverage:** patch keyed by id (Task 1, 4); unknown id adds, known replaces,
absent inherited (Task 1's `mergeReply`); no deletion form (stated, `--fresh` in
Task 2); inherit by default with `--fresh` (Task 2); `basis:` as a sealed input
(Task 2); prompt section (Task 3); `check_draft` judging inherited+patch (Task 5);
untouched lines keep their own stamps (Task 1's `mergeTouched`, wired in Task 4);
append-only untouched, so a run not covering every world still cannot move the
shared grammar (stated in the constraints, enforced by existing code);
measurement against errand 1's baseline (Task 6). The model default does not
move, as decided.

**Type consistency:** `replyLinesOf :: Maybe Text -> Text -> Text`,
`mergeReply :: Text -> Text -> Text`, `touchedIds :: Text -> [Text]`,
`mergeTouched :: [Text] -> Text -> Text -> Text` are defined in Task 1 and used
under those names and argument orders in Tasks 4 and 5. `record`'s new `basis`
parameter (Task 2) is passed in Task 4. `goFresh` (Task 2) reaches `generate` as
the `fresh` argument used in Task 4.

**Known soft spots, flagged not hidden:** (i) Task 4 Step 1 is written as shape
plus intent rather than final code, because the exact plumbing depends on how
`tryRead` and `governingRecord` compose there — the implementer must read those
two functions first. (ii) A patch that edits a pattern while another committed
world is absent from the run must be refused by `appendOnlyViolations`; add a
test for that in Task 4 if the existing suite does not already cover the
inherited-grammar case (grep `appendOnlyViolations` in `Spec.hs`).
