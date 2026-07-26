# Mint Expression Channels Implementation Plan (Plan B of three)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the mint explain the language it built and file the kernel capability it lacked, so a human reviewing a mint reads prose instead of reverse-engineering `.lang`, and a dead mint produces a work item instead of a shrug.

**Architecture:** Two new minted item kinds ride the heredoc block syntax that `source` already uses: `report` (exactly one per mint, plain language, written to `<language>/README.md`) and `gap` (zero or more, each naming a missing kernel capability, the line it blocks, and a minimal repro). Parsing lives in `Lips.Generate.Minting` beside the other items; rendering the README lives in a new `Lips.Generate.Readme`; `generate` writes the file, echoes a summary, and surfaces gaps in both the success and the refusal path. Regeneration additionally shows the model what it wrote last time (previous `.lang`, previous `README.md`, committed `.expect`) so vocabulary stays stable across mints.

**Tech Stack:** Haskell (GHC, `-Wall` clean), `hspec`.

## Global Constraints

- The kernel stays domain-blind; nothing here enters `Lips.Kernel.*` except nothing at all — all changes sit in the Generate tier and the CLI.
- Deduce-or-fail with a structural guard: a mint that ships no `report` block is incomplete and is refused, so the channel cannot rot into an optional pleasantry the model skips.
- Generated output is never hand-edited: `README.md` opens with a line saying so, and is overwritten on every successful mint.
- Invariant 6 is untouched: `.lang` stamping and `genId` keep working; the report and gaps are minted text carried by the same recorded reply.
- Layout rule: everything the machine writes for a language lives in `<language>/`. The report is `<language>/README.md`.
- The suite and app stay `-Wall` clean. Small single-line commits; worktree `.worktrees/mint-channels`, branch `feat/mint-channels`.
- Independent of Plan A (`2026-07-26-mint-schema-tool-plan.md`) and may land in either order: Plan A touches the tool wiring and the record, this plan touches the reply grammar and the refusal. The only shared file is `kernel/app/Main.hs`, in different functions.

## File Structure

- Create `kernel/src/Lips/Generate/Readme.hs` — `renderReadme :: Text -> Text -> [Gap] -> Text`, the generated-file header plus the model's prose plus a "Known gaps" section.
- Modify `kernel/src/Lips/Generate/Minting.hs` — `EngineItem` gains `ItemReport Text` and `ItemGap Gap`; `data Gap = Gap { gapSlug :: Text, gapBody :: Text }`; block parsing for both; `reportOf`, `gapsOf`.
- Modify `kernel/app/Main.hs` — require exactly one report, write `README.md`, echo its first lines, print gaps on success, include gaps in the refusal, and assemble the regeneration context.
- Modify `kernel/src/Lips/Identity.hs` — `readmePath :: FilePath -> FilePath` and `readmePathIn`.
- Modify `kernel/test/Spec.hs`, `README.md`, `DESIGN.md` (§13), `TODO.md`.

---

### Task 1: `readmePath`

**Files:**
- Modify: `kernel/src/Lips/Identity.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `readmePath :: FilePath -> FilePath` (`examples/ledger.backup.lips` → `examples/backup/README.md`) and `readmePathIn :: FilePath -> FilePath -> FilePath` (explicit directory, mirroring `artifactsPathIn`).

- [ ] **Step 1: Write the failing test**

```haskell
    it "the language's report sits in the language folder as README.md" $ do
      readmePath "examples/ledger.backup.lips" `shouldBe` "examples/backup/README.md"
      readmePath "backup.lips"                 `shouldBe` "backup/README.md"
```

- [ ] **Step 2: Run and watch it fail.** Expected: `Variable not in scope: readmePath`.

- [ ] **Step 3: Implement**

```haskell
-- | The language's minted explanation: @examples/backup/README.md@. Named
-- README rather than @<language>.md@ because it is prose for a human, and
-- README is the one filename every reader and forge already resolves to "read
-- this first"; its first line warns that regeneration overwrites it.
readmePath :: FilePath -> FilePath
readmePath file = langDir file </> "README.md"

readmePathIn :: FilePath -> FilePath -> FilePath
readmePathIn dir _file = dir </> "README.md"
```

Export both.

- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git commit -am "identity: name the language folder's minted README"
```

---

### Task 2: Parse the `report` Block

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `EngineItem` gains `ItemReport Text` (the verbatim block body).
- `reportOf :: [EngineItem] -> Maybe Text` (the first report; a second one is a parse error, see Task 4's guard in `Main`).
- Syntax, reusing the existing heredoc machinery in `parseEngineCandidates`:

```
0.95 d1 report <<<lips
...markdown, verbatim...
lips>>>
```

The header prefix is `<confidence> <id> report`, matching `source`'s `<confidence> <id> source <name> <relpath>`. `mkSource` currently owns the header parse; generalize it into `mkBlock` dispatching on the keyword (`source` | `report` | `gap`).

- [ ] **Step 1: Write the failing test**

```haskell
    it "a report block carries verbatim prose" $ do
      let reply = "0.9 d1 report <<<lips\n# The backup language\n\nreads two shapes.\nlips>>>\n"
          (errs, cands) = parseEngineCandidates reply
      errs `shouldBe` []
      reportOf (map icItem cands) `shouldBe` Just "# The backup language\n\nreads two shapes."
```

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Implement**

Generalize the block header parser:

```haskell
-- | Parse a block header and pair it with its collected content. Three block
-- kinds share the heredoc so anything verbatim (program source, prose, a bug
-- report) can be carried without escaping: @source <name> <relpath>@,
-- @report@, @gap <slug>@.
mkBlock :: Text -> Text -> Text -> Either Text ItemCandidate
mkBlock prefix rawHeader content = do
  (confTok, r1) <- firstToken prefix ("empty block header: " <> rawHeader)
  (idTok, r2)   <- firstToken r1 ("no id in block header: " <> rawHeader)
  conf          <- parseConfidence confTok
  item <- case T.words r2 of
    ["source", name, relpath] -> Right (ItemSource (SourceFile name relpath content))
    ["report"]                -> Right (ItemReport content)
    ["gap", slug]             -> Right (ItemGap (Gap slug content))
    _ -> Left ("block header must be '<confidence> <id> source <name> <relpath>', \
               \'<confidence> <id> report' or '<confidence> <id> gap <slug>': " <> rawHeader)
  Right (ItemCandidate item (Confidence conf) rawHeader idTok)
```

Add `reportOf` and keep `sourcesOf` filtering as before. `assemble`, `expectsOf` ignore the new constructors (they pattern-match by constructor already).

- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git commit -am "mint: accept a report block, the language's explanation in the model's words"
```

---

### Task 3: Parse the `gap` Block

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `data Gap = Gap { gapSlug :: Text, gapBody :: Text } deriving (Eq, Show)`
- `gapsOf :: [EngineItem] -> [Gap]`

- [ ] **Step 1: Write the failing test**

```haskell
    it "a gap block names a missing capability and its repro" $ do
      let reply = "0.4 g1 gap templated-source <<<lips\nblocked line: - /hi => status 200\nsource heredocs have no holes, so a per-route body cannot reach the compiled source.\nlips>>>\n"
          (errs, cands) = parseEngineCandidates reply
      errs `shouldBe` []
      map gapSlug (gapsOf (map icItem cands)) `shouldBe` ["templated-source"]
```

- [ ] **Step 2: Run and watch it fail.**
- [ ] **Step 3: Implement** `Gap`, the `ItemGap` constructor (already dispatched in Task 2's `mkBlock`), and

```haskell
-- | The capability the mint found missing. A gap is not an excuse: it is a bug
-- filed against the kernel in the model's own words (invariant 4 -- a mint that
-- needs gymnastics means the physics is short, and the fix belongs in the
-- kernel, never in the prompt or in hand-edited output).
gapsOf :: [EngineItem] -> [Gap]
gapsOf items = [g | ItemGap g <- items]
```

Also exclude `ItemGap` and `ItemReport` from the confidence gate the way `ItemNote` already is (a gap is honest at low confidence by nature): in `Main`'s `unsure` filter, replace the local `notNote` with `carriesEngineMeaning`, exported from `Minting` as the one place that says which items the threshold governs, so a future item kind cannot silently fall under the gate by omission.

- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git commit -am "mint: accept a gap block, a kernel bug filed by the mint"
```

---

### Task 4: Write the README and Surface Gaps

**Files:**
- Create: `kernel/src/Lips/Generate/Readme.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `renderReadme :: Text -> Text -> [Gap] -> Text` — language name, report body, gaps.

- [ ] **Step 1: Write the failing test**

```haskell
    it "the README warns it is generated and lists the gaps" $ do
      let out = renderReadme "backup" "reads three shapes." [Gap "templated-source" "no holes in source blocks"]
      out `shouldSatisfy` T.isInfixOf "lips generate"
      out `shouldSatisfy` T.isInfixOf "reads three shapes."
      out `shouldSatisfy` T.isInfixOf "templated-source"
```

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Implement**

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | The language's minted explanation, rendered for a human. The engine is
-- exact but terse; this is the only place the mint speaks plainly about what it
-- built, which mechanism it chose, and what it had to invent. Overwritten by
-- every successful mint, so it can never describe a language that is no longer
-- there.
module Lips.Generate.Readme (renderReadme) where

import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Generate.Minting (Gap (..))

renderReadme :: Text -> Text -> [Gap] -> Text
renderReadme lang body gaps = T.unlines $
  [ "<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->"
  , ""
  , "# The `" <> lang <> "` language"
  , ""
  , T.strip body
  ] ++ gapSection
  where
    gapSection
      | null gaps = []
      | otherwise = [ "", "## Known gaps", "" ] ++ concat
          [ [ "### " <> gapSlug g, "", T.strip (gapBody g), "" ] | g <- gaps ]
```

- [ ] **Step 4: Run the test.** Expected: PASS.

- [ ] **Step 5: Wire it into `generate`**

In `kernel/app/Main.hs`, after the candidates are parsed and before the confidence gate, add the structural guard:

```haskell
      -- A mint without an explanation is incomplete: the human's review artifact
      -- is the report, not the .lang. Structural guard rather than a prompt plea.
      reportBody <- case reportOf (map icItem candidates) of
        Just b  -> pure b
        Nothing -> die (report
          ("the mint for ." <> T.pack lang <> " came back without a report block.")
          ["lips needs the language explained in plain words before it commits it."]
          "→ run generate again.")
```

After the write block (beside `TIO.writeFile (generationPath rep) rec`):

```haskell
      TIO.writeFile (readmePath rep) (renderReadme (T.pack lang) reportBody (gapsOf (map icItem candidates)))
```

Extend the success summary on stderr with the first five non-empty lines of `reportBody`, then `"→ read the whole account: " <> T.pack (readmePath rep)`, and, when gaps exist:

```haskell
        ++ [ "", "lips could not do these, and says why in " <> T.pack (readmePath rep) <> ":" ]
        ++ [ "  - " <> gapSlug g | g <- gapsOf (map icItem candidates) ]
```

- [ ] **Step 6: Surface gaps in the refusal**

Change `refusalReport` to take `[Gap]` and append, when non-empty:

```haskell
      [ "", "The mint says lips is missing a capability here:" ]
      ++ concat [ [ "  - " <> gapSlug g ] ++ [ "      " <> l | l <- T.lines (T.strip (gapBody g)) ] | g <- gaps ]
      ++ [ "", "→ this is a lips bug, not your program. Please report the text above." ]
```

- [ ] **Step 7: Verify end to end**

```bash
git add . && just generate examples/ledger.backup.lips
cat examples/backup/README.md
```
Expected: a generated-file header, prose about the backup language, no gaps section.

- [ ] **Step 8: Commit**

```bash
git add kernel/src/Lips/Generate/Readme.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "generate: write the language README and surface the mint's gaps"
```

---

### Task 5: Regeneration Context

**Files:**
- Modify: `kernel/app/Main.hs`
- Test: manual (the corpus is assembled inline; the shape is asserted by reading a `.generation` record)

**Interfaces:**
- The user prompt (`corpus`) gains, when the files exist, three blocks appended after the programs:

```
=== previous engine backup.lang ===
…
=== previous report README.md ===
…
=== committed contract backup.expect ===
…
```

- [ ] **Step 1: Implement**

```haskell
  -- Regeneration sees what the last mint produced, so a re-mint keeps the
  -- vocabulary and mechanism it already taught the human unless something
  -- forces a change; a gratuitously renamed subject makes the diff unreadable
  -- and the .expect gate fire for no reason. The programs stay the only truth:
  -- the prompt says so, and nothing here promotes the old engine to evidence.
  prevLang   <- tryRead (langPath rep)
  prevReport <- tryRead (readmePath rep)
  prevExpect <- if renew then pure Nothing else tryRead (expectPath rep)
  let priorBlock name = maybe [] (\t -> ["=== " <> name <> " ===\n" <> t])
      corpus = T.intercalate "\n" $
        [ "=== program " <> T.pack (takeFileName f) <> " ===\n" <> t | (f, t) <- progs ]
        ++ priorBlock ("previous engine " <> T.pack (takeFileName (langPath rep))) prevLang
        ++ priorBlock "previous report README.md" prevReport
        ++ priorBlock ("committed contract " <> T.pack (takeFileName (expectPath rep))) prevExpect
```

`--renew` deliberately withholds the committed contract: the run exists to re-bless behavior, so showing the old contract would anchor the mint to what the human just chose to abandon.

- [ ] **Step 2: Verify**

Regenerate a language that already has an engine and confirm the `.generation` record's `--- program (input) ---` section carries the three extra blocks, and that the new `.lang` keeps the previous subject names.

- [ ] **Step 3: Commit**

```bash
git commit -am "generate: show a re-mint what the last one built, so vocabulary stays stable"
```

---

### Task 6: Docs

**Files:** `README.md`, `DESIGN.md` (§13), `TODO.md`, `kernel/README.md`

- [ ] **Step 1: README** — add `backup/README.md` to "The Files" table (author: AI, once; role: the language explained; in git: yes) and to the directory listing.
- [ ] **Step 2: DESIGN §13** — Done entry for the report and gap channels; note that TODO item 2 (`<program>.gap`) now has a producer and only needs the file writer.
- [ ] **Step 3: TODO.md** — narrow item 2 accordingly.
- [ ] **Step 4: kernel/README.md** — add `Lips/Generate/Readme.hs` to the module map.
- [ ] **Step 5: Commit**

```bash
git commit -am "docs: the mint explains itself in README.md and files gaps"
```

## Self-Review

- Spec coverage: report block parsed (Task 2), written to `<language>/README.md` with a generated-file header and echoed on stderr (Tasks 1, 4), gap block parsed and surfaced on both the success and refusal paths (Tasks 3, 4), regeneration context (Task 5).
- Structural guard: exactly one report is required; a missing one refuses the mint (Task 4, Step 5).
- Names used consistently: `Gap`, `gapSlug`, `gapBody`, `reportOf`, `gapsOf`, `renderReadme`, `readmePath`.
</content>
