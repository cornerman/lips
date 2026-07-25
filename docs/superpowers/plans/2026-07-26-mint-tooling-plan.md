# Mint Tooling Implementation Plan (Plan A of three)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the mint from a blind single shot into a bounded, self-verifying agent loop: the model may query the pinned option schema and dry-run a draft engine through the exact gate `generate` runs, within a budget it knows about, and the whole transcript is recorded.

**Architecture:** The gate mechanism moves out of `kernel/app/Main.hs` into a reusable `Lips.Generate.Gate`, so `generate` and a new `lips dry-run` verb run identical checks by construction. Two new read-only verbs (`lips options <query>`, `lips dry-run <programs…>`) carry the logic in Haskell; a small shipped pi extension (`assets/mint-tools.ts`) registers exactly two custom tools that shell out to them, and `callPi` runs pi with built-in tools, ambient extensions, skills and prompt templates all disabled, so those two tools are the only reachable action. A new `--rounds N` flag (default 8) bounds the loop, is stated to the model, is enforced by the extension, and enters the `.generation` record.

**Tech Stack:** Haskell (GHC, `-Wall` clean), `optparse-applicative`, `aeson`, `hspec`, TypeScript (one pi extension file), Nix flakes, `just`.

## Global Constraints

- The kernel is domain-blind: nothing in `Lips.Kernel.*` learns a NixOS name. Schema knowledge stays in `Lips.Nix.Options`; the new query helper on the generic schema lives in `Lips.Kernel.OptionType` and mentions no NixOS string. (`AGENTS.md`, "The Kernel Knows Nothing".)
- Invariant 1 holds: `compile` and `check` never call a model and never reach the new tools.
- Deduce-or-fail: the dry-run is advisory only. `generate`'s own full gate still runs before anything is written, unchanged.
- Invariant 6: `.generation` must remain a true, self-contained account of the mint; whatever the model saw goes in, and `genId` hashes it.
- The suite and app stay `-Wall` clean.
- Nix flakes see only git-tracked files: `git add` before `nix build`/`nix run`.
- Work in a worktree under `.worktrees/mint-tooling`, branch `feat/mint-tooling`. Small single-line commits, rebase + ff-merge to main.
- Fast test loop from `kernel/`: `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`.

## File Structure

- Create `kernel/src/Lips/Generate/Gate.hs` — the gate mechanism shared by `generate` and `dry-run`: `Failure`, `ExpectFail`, `NixParse`, `validate`, `nixParses`, `runExpects`, `writeSources`, `stageFromDisk`, `mkTempDir`. No message wording (that stays in `Main`).
- Create `assets/mint-tools.ts` — the pi extension registering `lips_options` and `lips_dry_run`, enforcing the dry-run budget.
- Modify `kernel/src/Lips/Kernel/OptionType.hs` — add `queryOptions` (domain-blind path search over `OptionSchema`).
- Modify `kernel/src/Lips/Cli.hs` — add `Options`/`DryRun` commands, `--rounds`.
- Modify `kernel/app/Main.hs` — dispatch the two verbs, use `Lips.Generate.Gate`, rewire `callPi`, thread `--rounds`.
- Modify `kernel/src/Lips/Generate/PiJson.hs` — recover the full transcript, not just the final assistant text.
- Modify `kernel/src/Lips/Generate/Record.hs` — record the transcript and the rounds budget.
- Modify `kernel/src/Lips/Generate/Minting.hs` — append the budget statement to the system prompt (`promptWithBudget`).
- Modify `flake.nix` — install `assets/mint-tools.ts` into the package and bake `LIPS_MINT_TOOLS`.
- Modify `kernel/test/Spec.hs`, `README.md`, `DESIGN.md` (§13), `kernel/README.md`, `TODO.md`.

Dependencies: Task 1 (gate extraction) precedes Tasks 3 and 5. Task 2 (schema query) is independent. Task 6 (extension + wiring) consumes Tasks 2, 3, 4. Task 7 (provenance) consumes Task 6.

---

### Task 1: Extract the Gate

**Files:**
- Create: `kernel/src/Lips/Generate/Gate.hs`
- Modify: `kernel/app/Main.hs` (delete the moved definitions, import them)

**Interfaces:**
- Produces, all moved verbatim from `Main.hs` (same signatures, same behavior):
  - `data Failure = FailRead [CrystError] | FailRun RunError`
  - `data ExpectFail = ToolMissing Text | EvalFailed Text | Violations [Text]`
  - `data NixParse = NixToolMissing Text | NixInvalid Text`
  - `validate :: FilePath -> EngineData -> Text -> Either Failure (Base, Text, Maybe (Text, [Text]))`
  - `nixParses :: Text -> IO (Either NixParse ())`
  - `runExpects :: (FilePath -> IO ()) -> [Expect] -> Base -> Text -> IO (Either ExpectFail ())`
  - `writeSources :: FilePath -> [SourceFile] -> IO ()`
  - `stageFromDisk :: FilePath -> FilePath -> FilePath -> IO ()`
  - `mkTempDir :: IO FilePath`
  - `budget :: Int` (the refinement step budget, renamed `stepBudget` to free the word for the new round budget)
- Consumes: unchanged imports from `Lips.Kernel.*`, `Lips.Identity`, `Lips.Generate.Minting`.

- [ ] **Step 1: Move the definitions**

Cut `Failure`, `ExpectFail`, `NixParse`, `validate`, `nixParses`, `runExpects`, `writeSources`, `stageFromDisk`, `mkTempDir`, `parentDir`, `shq`, and `budget` (renamed `stepBudget`) from `kernel/app/Main.hs` into a new `kernel/src/Lips/Generate/Gate.hs` with module header:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | The deterministic gate a candidate engine must pass: crystallize every
-- program, realize it, parse the result as Nix, and evaluate the behavioral
-- contract against it. Extracted from the CLI so @generate@ and @lips
-- dry-run@ run the SAME checks by construction -- a dry-run verdict the model
-- trusts must be the verdict that later decides whether anything is written.
-- Mechanism only: every user-facing wording stays in @Main@.
module Lips.Generate.Gate
  ( Failure (..), ExpectFail (..), NixParse (..)
  , validate, nixParses, runExpects
  , writeSources, stageFromDisk, mkTempDir
  , stepBudget, shq, parentDir
  ) where
```

- [ ] **Step 2: Re-point Main**

In `kernel/app/Main.hs` add `import Lips.Generate.Gate` with an explicit import list matching the export list above, delete the moved code, and replace every `budget` use with `stepBudget`.

- [ ] **Step 3: Verify nothing changed**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: PASS, no warnings. Then `just compile examples/ledger.backup.lips` still prints the module and the nix commands.

- [ ] **Step 4: Commit**

```bash
git add kernel/src/Lips/Generate/Gate.hs kernel/app/Main.hs
git commit -m "gate: extract the engine gate from the CLI so generate and dry-run share it"
```

---

### Task 2: Schema Query (`queryOptions` and `lips options`)

**Files:**
- Modify: `kernel/src/Lips/Kernel/OptionType.hs`
- Modify: `kernel/src/Lips/Cli.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- Produces: `queryOptions :: Int -> Text -> OptionSchema -> ([( [Text], OptionType )], Int)` — matches sorted by path; the second component is how many further matches were elided by the cap. A match is a path whose dotted rendering has the query as a prefix, or, failing that, contains it as a substring (case-sensitive; option names are lowercase-dotted by convention, and the kernel must not invent a casing rule).
- Consumes: `OptionSchema`, `renderOptionType` (already in the module), `dotted` (already private; export it or reuse `T.intercalate "."`).
- Produces (CLI): `Command` gains `Options OptionsOpts`; `data OptionsOpts = OptionsOpts { ooTarget :: Target, ooLimit :: Int, ooQuery :: String }`.

- [ ] **Step 1: Write the failing test**

Add to `kernel/test/Spec.hs`, in a new `describe "option schema query (the mint's lookup tool)"`:

```haskell
    let sch = Map.fromList
          [ (["services","restic","backups","<name>","paths"], OTListOf OTString)
          , (["services","restic","backups","<name>","repository"], OTString)
          , (["services","nginx","enable"], OTBool)
          ]
    it "a dotted prefix lists the subtree" $
      fst (queryOptions 10 "services.restic" sch) `shouldBe`
        [ (["services","restic","backups","<name>","paths"], OTListOf OTString)
        , (["services","restic","backups","<name>","repository"], OTString) ]
    it "a bare word falls back to substring search" $
      map fst (fst (queryOptions 10 "nginx" sch)) `shouldBe` [["services","nginx","enable"]]
    it "the cap reports how many matches were elided" $
      snd (queryOptions 1 "services" sch) `shouldBe` 2
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec`
Expected: FAIL, `Variable not in scope: queryOptions`.

- [ ] **Step 3: Implement `queryOptions`**

In `kernel/src/Lips/Kernel/OptionType.hs`:

```haskell
-- | Search a schema by path. A mint has to name real options; this is the
-- lookup it does before emitting a rule. Prefix first (browsing a namespace),
-- substring as the fallback (the caller does not know the namespace yet). The
-- cap keeps a tool result readable and reports what it hid, so the caller can
-- narrow instead of silently seeing a slice.
queryOptions :: Int -> Text -> OptionSchema -> ([([Text], OptionType)], Int)
queryOptions cap q sch = (take cap hits, max 0 (length hits - cap))
  where
    hits = if null byPrefix then bySubstring else byPrefix
    byPrefix    = [ e | e@(p, _) <- Map.toAscList sch, q `T.isPrefixOf` dotted p ]
    bySubstring = [ e | e@(p, _) <- Map.toAscList sch, q `T.isInfixOf`  dotted p ]
```

Export `queryOptions` and `dotted`.

- [ ] **Step 4: Run the test**

Run the fast loop. Expected: PASS.

- [ ] **Step 5: Add the CLI verb**

In `kernel/src/Lips/Cli.hs`:

```haskell
data OptionsOpts = OptionsOpts
  { ooTarget :: Target
  , ooLimit  :: Int
  , ooQuery  :: String
  } deriving (Eq, Show)
```

Add `| Options OptionsOpts` to `Command`, and to `cliParser`:

```haskell
  <> command "options"
       (info (Options <$> optionsOpts)
             (progDesc "List option paths and their types from the pinned schema (the mint's lookup)."))
```

```haskell
optionsOpts :: Parser OptionsOpts
optionsOpts = OptionsOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar "nixos|home-manager" <> help "Which world's schema to search (default: nixos).")
  <*> option auto
        (long "limit" <> value 40 <> metavar "N" <> help "Maximum matches to print (default: 40).")
  <*> strArgument (metavar "QUERY" <> help "A dotted option prefix, or any substring of a path.")
```

- [ ] **Step 6: Implement the verb in Main**

Add to the `case cmd of` dispatch: `Options oo -> optionsQuery (ooTarget oo) (ooLimit oo) (T.pack (ooQuery oo))`, and:

```haskell
-- | @options@: print option paths and types from the pinned schema. The mint's
-- lookup tool, and a human's too: a rule may only name an option that exists,
-- so being able to ask is the difference between a checked answer and a recalled
-- one. Read-only, offline (after the schema is built once) and model-free.
optionsQuery :: Target -> Int -> Text -> IO ()
optionsQuery target limit q = do
  schemaPath <- ensureOptionSchema target "options"
  bytes <- BL.readFile schemaPath
  case parseNixOptionsJson bytes of
    Left why -> die (report ("lips can't parse the option schema at " <> T.pack schemaPath <> ":") [why]
                            "→ run generate again to rebuild it.")
    Right schema -> do
      let (hits, elided) = queryOptions limit q schema
      forM_ hits $ \(p, t) -> TIO.putStrLn (dotted p <> " : " <> renderOptionType t)
      if null hits
        then TIO.putStrLn ("no option matches " <> q)
        else if elided > 0
          then TIO.putStrLn ("… " <> tshow elided <> " more matches; narrow the query or raise --limit.")
          else pure ()
```

`ensureOptionSchema`'s second argument is only used in error wording, so passing `"options"` is fine; adjust its type comment.

- [ ] **Step 7: Verify by hand**

Run: `nix run . -- options services.restic.backups`
Expected: lines like `services.restic.backups.<name>.paths : list of string`.

- [ ] **Step 8: Commit**

```bash
git add kernel/src/Lips/Kernel/OptionType.hs kernel/src/Lips/Cli.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "cli: add lips options, a schema lookup over the pinned option set"
```

---

### Task 3: The `lips dry-run` Verb

**Files:**
- Modify: `kernel/src/Lips/Cli.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs` (CLI parser only; the verb itself is IO over nix and is exercised by the flake check)

**Interfaces:**
- Produces (CLI): `Command` gains `DryRun DryRunOpts`; `data DryRunOpts = DryRunOpts { droTarget :: Target, droFiles :: [FilePath] }`.
- Produces (Main): `dryRunVerb :: Target -> [FilePath] -> IO ()` — reads a candidate `.lang` from **stdin**, runs the same gate `generate` runs against every named program, prints findings to stdout, exits 0 when green and 1 when not.

Behavior, in the same order as `generate`, stopping at the first stage that produces findings (a later stage cannot be meaningful once an earlier one failed):

1. `readLang` the stdin text → parse errors, each `line N: message`.
2. `assertOptionsAdmissible`-equivalent: `checkEmits` against the pinned schema → `renderOptionError` lines.
3. Per program: `validate` → `failureReport`; then `nixParses` → the invalid-Nix text.
4. `runExpects` with the committed `.expect` when the language folder has one, else with no contract (a draft has none yet on a first mint) → violation lines.

Green output is exactly `ok: <n> program(s) crystallize, realize, parse as Nix and satisfy the contract.`

- [ ] **Step 1: Write the failing parser test**

Add to `kernel/test/Spec.hs` where the other `Lips.Cli` parser tests live:

```haskell
    it "dry-run takes a target and one or more programs" $
      parseArgs ["dry-run", "--target", "nixos", "a.backup.lips", "b.backup.lips"]
        `shouldBe` Just (DryRun (DryRunOpts Nixos ["a.backup.lips", "b.backup.lips"]))
```

(Reuse the existing helper the CLI tests use to run `execParserPure`; if none exists, add `parseArgs :: [String] -> Maybe Command` there.)

- [ ] **Step 2: Run it and watch it fail**

Expected: FAIL, `Data constructor not in scope: DryRun`.

- [ ] **Step 3: Add the grammar**

In `kernel/src/Lips/Cli.hs`, mirroring `generateOpts`:

```haskell
data DryRunOpts = DryRunOpts
  { droTarget :: Target
  , droFiles  :: [FilePath]
  } deriving (Eq, Show)

dryRunOpts :: Parser DryRunOpts
dryRunOpts = DryRunOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar "nixos|home-manager" <> help "The world to realize into (default: nixos).")
  <*> some (strArgument (metavar "PROGRAM..." <> completer programCompleter))
```

and the subcommand:

```haskell
  <> command "dry-run"
       (info (DryRun <$> dryRunOpts)
             (progDesc "Check a candidate engine (read from stdin) against programs, exactly as generate does."))
```

- [ ] **Step 4: Run the test**

Expected: PASS.

- [ ] **Step 5: Implement the verb**

In `kernel/app/Main.hs`:

```haskell
-- | @dry-run@: run a CANDIDATE engine (stdin) through the same gate @generate@
-- applies, and report what it would say. The mint's rehearsal tool: a model
-- that can see the verdict fixes its own engine instead of dying on it, and
-- because the checks are literally the ones @generate@ runs
-- ('Lips.Generate.Gate'), a green rehearsal cannot disagree with the real gate.
-- Read-only: it writes nothing, and it never calls a model.
dryRunVerb :: Target -> [FilePath] -> IO ()
dryRunVerb target files = do
  draft <- TIO.getContents
  progs <- forM files (\f -> (,) f <$> readProgramOrDie f)
  case readLang draft of
    Left es -> finish [ "the engine text does not parse:" ]
                      [ renderParseError e | e <- es ]
    Right eng -> do
      schemaPath <- ensureOptionSchema target (head files)
      bytes <- BL.readFile schemaPath
      schema <- either (die . T.pack . show) pure (first show (parseNixOptionsJson bytes))
      case map renderOptionError (checkEmits schema (edRules eng)) of
        errs@(_ : _) -> finish ["rules name options that do not exist or have the wrong type:"] errs
        [] -> do
          results <- forM progs $ \(f, t) -> case validate f eng t of
            Left ff -> pure (Left (failureReport f ff))
            Right (base, nixMod, _) -> do
              parsed <- nixParses nixMod
              case parsed of
                Left (NixToolMissing e) -> die (nixMissing f "dry-run the engine" "dry-run" e)
                Left (NixInvalid why)   -> pure (Left (T.pack f <> ": the module is not valid Nix:\n" <> why))
                Right () -> pure (Right (f, base, nixMod))
          case [ e | Left e <- results ] of
            errs@(_ : _) -> finish [] errs
            [] -> do
              committed <- tryRead (expectPath (head files))
              expects <- case maybe (Right []) readExpect committed of
                Left es -> die (unreadable (expectPath (head files)) "" es)
                Right xs -> pure xs
              gaps <- forM [ r | Right r <- results ] $ \(f, base, nixMod) -> do
                gate <- runExpects (const (pure ())) (map (bindSelfExpect (instanceName f)) expects) base nixMod
                pure $ case gate of
                  Left (ToolMissing e) -> [T.pack f <> ": nix could not run: " <> e]
                  Left (EvalFailed e)  -> [T.pack f <> ": the module does not evaluate: " <> e]
                  Left (Violations fs) -> [T.pack f <> ": " <> v | v <- fs]
                  Right ()             -> []
              case concat gaps of
                []   -> TIO.putStrLn ("ok: " <> tshow (length files)
                          <> " program(s) crystallize, realize, parse as Nix and satisfy the contract.")
                errs -> finish ["the contract does not hold:"] errs
  where
    finish headline errs = do
      mapM_ TIO.putStrLn (headline ++ map ("  - " <>) errs)
      exitFailure
```

Note: artifact sources are not staged here, so an engine whose expects touch an artifact path is checked exactly as `generate` checks it (`generate` stages minted sources; a dry-run has none on disk yet). Document that in the tool description in Task 6 so the model knows.

Wire the dispatch: `DryRun dro -> dryRunVerb (droTarget dro) (droFiles dro)`.

- [ ] **Step 6: Verify by hand**

```bash
nix run . -- dry-run examples/ledger.backup.lips < examples/backup/backup.lang
```
Expected: `ok: 1 program(s) …`. Then corrupt one rule's option path in a copy and confirm the verdict names it.

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "cli: add lips dry-run, the mint's rehearsal against the real gate"
```

---

### Task 4: The `--rounds` Budget

**Files:**
- Modify: `kernel/src/Lips/Cli.hs`
- Modify: `kernel/src/Lips/Generate/Minting.hs`
- Modify: `kernel/src/Lips/Generate/Record.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `GenerateOpts` gains `goRounds :: Int`; flag `--rounds N`, default from a new `defaultRounds :: Int` in `Main` (value `8`), passed to `cliParserInfo` beside `defaultConfidence`.
- `promptWithBudget :: Int -> Text -> Text` in `Minting` — appends the budget statement to a composed prompt.
- `record` gains a rounds argument, printed as `rounds: N` right after `confidence-threshold:`.

- [ ] **Step 1: Write the failing tests**

```haskell
    it "the budget is stated to the model as a number" $
      promptWithBudget 8 "BODY" `shouldSatisfy` T.isInfixOf "8 dry-run"
    it "the record pins the round budget, so genId changes with it" $
      genId (record "m" Nixos 0.7 8 "p" "prog" "reply")
        `shouldNotBe` genId (record "m" Nixos 0.7 4 "p" "prog" "reply")
```

- [ ] **Step 2: Run and watch it fail.** Expected: `Variable not in scope: promptWithBudget`.

- [ ] **Step 3: Implement**

In `Minting`:

```haskell
-- | State the loop budget as a NUMBER the model can pace itself against. It is
-- not a hidden constant: the same number bounds the tool (the extension refuses
-- past it) and enters the generation record, so the event is reproducibly
-- described by what the model was told.
promptWithBudget :: Int -> Text -> Text
promptWithBudget n p = p <> T.unlines
  [ ""
  , "BUDGET: you may call lips_dry_run at most " <> T.pack (show n) <> " times in"
  , "this mint. Every result tells you how many calls remain. Spend the last one"
  , "verifying the engine you are about to answer with. If the budget runs out"
  , "before the engine is green, do not guess: answer with your best engine and a"
  , "gap block naming what blocked you."
  ]
```

In `Record.record`, add the parameter and the `rounds: ` line. In `Cli.generateOpts`, add

```haskell
  <*> option auto (long "rounds" <> value defRounds <> metavar "N"
        <> help "How many dry-run rounds the mint may spend (default: 8).")
```

threading `defRounds` through `cliParserInfo :: Double -> Int -> ParserInfo Command`.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git commit -am "generate: --rounds N bounds the mint loop, stated to the model and pinned in the record"
```

---

### Task 5: The pi Extension

**Files:**
- Create: `assets/mint-tools.ts`
- Modify: `flake.nix`

**Interfaces:**
- Consumes env: `LIPS_BIN` (absolute path to the lips binary), `LIPS_DRY_RUN_BUDGET` (integer), `LIPS_MINT_PROGRAMS` (newline-separated program paths), `LIPS_MINT_TARGET` (`nixos`|`home-manager`).
- Registers two tools: `lips_options({ query })` and `lips_dry_run({ engine })`.

- [ ] **Step 1: Write the extension**

`assets/mint-tools.ts`:

```typescript
// The ONLY actions a lips mint may take. pi runs the mint with built-in tools,
// ambient extensions, skills and prompt templates disabled, so this file is the
// mint's complete world: look up an option, or rehearse a draft engine against
// the real gate. Both shell out to the lips binary, so the behaviour the model
// sees is the behaviour that later judges it.
import { spawnSync } from "node:child_process";

const bin = process.env.LIPS_BIN ?? "lips";
const target = process.env.LIPS_MINT_TARGET ?? "nixos";
const programs = (process.env.LIPS_MINT_PROGRAMS ?? "").split("\n").filter(Boolean);
const budget = Number(process.env.LIPS_DRY_RUN_BUDGET ?? "8");
let spent = 0;

const run = (args: string[], stdin?: string) => {
  const r = spawnSync(bin, args, { input: stdin ?? "", encoding: "utf8" });
  return [r.stdout ?? "", r.stderr ?? ""].filter(Boolean).join("\n");
};

export default function (pi: any) {
  pi.registerTool({
    name: "lips_options",
    description:
      "Search the pinned option schema of the target world. QUERY is a dotted " +
      "prefix (browse a namespace) or any substring of a path. Returns 'path : type' " +
      "lines. Every option a rule names must appear here, or the mint is rejected.",
    parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] },
    async execute(_id: string, params: { query: string }) {
      return { output: run(["options", "--target", target, params.query]) };
    },
  });

  pi.registerTool({
    name: "lips_dry_run",
    description:
      "Rehearse a candidate engine against the exact gate that decides this mint: " +
      "every program crystallizes, realizes, parses as Nix, its rules name real and " +
      "correctly typed options, and the committed contract holds. Pass the whole " +
      "engine as .lang text. Artifact sources are not staged, so an artifact build is " +
      "not exercised here.",
    parameters: { type: "object", properties: { engine: { type: "string" } }, required: ["engine"] },
    async execute(_id: string, params: { engine: string }) {
      if (spent >= budget) {
        return {
          output:
            `budget exhausted: ${budget} of ${budget} dry-run calls used. ` +
            `Answer now with your best engine, and a gap block if it is not green.`,
        };
      }
      spent += 1;
      const out = run(["dry-run", "--target", target, ...programs], params.engine);
      return { output: `${out}\n\nbudget: ${spent} of ${budget} used, ${budget - spent} left.` };
    },
  });
}
```

Check the exact `registerTool` signature against `/nix/store/…/libexec/pi/docs/extensions.md` before finishing, and adapt names (`parameters` may want a typebox schema); the semantics above must survive any signature change.

- [ ] **Step 2: Install it in the package**

In `flake.nix`, inside the `packages.default` builder, after the binary is built:

```bash
  install -Dm444 ${./assets/mint-tools.ts} "$out/share/lips/mint-tools.ts"
```

and extend the wrapper:

```bash
    --set-default LIPS_MINT_TOOLS "$out/share/lips/mint-tools.ts" \
    --set-default LIPS_BIN "$out/bin/lips" \
```

- [ ] **Step 3: Verify**

```bash
git add . && nix build . && ls result/share/lips/mint-tools.ts
```

- [ ] **Step 4: Commit**

```bash
git add assets/mint-tools.ts flake.nix
git commit -m "mint: ship the pi extension exposing exactly two tools to the mint"
```

---

### Task 6: Rewire `callPi`

**Files:**
- Modify: `kernel/app/Main.hs`

**Interfaces:**
- `callPi :: Maybe String -> Text -> Text -> MintEnv -> IO (Text, Text, Text)` returning reply, model, and transcript, where
  `data MintEnv = MintEnv { meTarget :: Target, mePrograms :: [FilePath], meRounds :: Int }`.

- [ ] **Step 1: Change the invocation**

```haskell
callPi mmodel system userPrompt env = do
  toolsPath <- lookupEnv "LIPS_MINT_TOOLS"
  extArgs <- case toolsPath of
    Just p  -> pure ["-e", p]
    Nothing -> die (report
      "lips can't run the mint: its tool extension is not installed."
      ["LIPS_MINT_TOOLS is unset."]
      "→ run the packaged lips: nix run . -- generate <program>")
  (code, out, err) <- readProcessWithExitCode "pi"
    -- Hermetic by explicit subtraction: -nbt drops the built-in tools,
    -- --no-extensions/--no-skills/--no-prompt-templates drop whatever the user
    -- has installed, -nc drops ambient AGENTS.md. What is left is the two tools
    -- this run loads on purpose, so the mint's world equals what the record pins.
    ([ "-p", "-nbt", "-nc", "--no-extensions", "--no-skills", "--no-prompt-templates"
     , "--no-session", "--mode", "json", "--system-prompt", T.unpack system ]
      ++ extArgs ++ maybe [] (\m -> ["--model", m]) mmodel)
    (T.unpack userPrompt)
```

with the environment for the child set by `System.Process`'s `proc`/`env` fields (switch from `readProcessWithExitCode` to `readCreateProcessWithExitCode (proc "pi" args) { env = Just inherited ++ mintVars }`), where `mintVars` sets `LIPS_MINT_TARGET`, `LIPS_MINT_PROGRAMS`, `LIPS_DRY_RUN_BUDGET`.

- [ ] **Step 2: Verify end to end**

```bash
git add . && just generate examples/hello.http.lips
```
Expected: pi's json stream shows `lips_dry_run` tool calls; the mint still writes the engine only when the real gate passes.

- [ ] **Step 3: Commit**

```bash
git commit -am "generate: run the mint with exactly two tools and an explicit hermetic environment"
```

---

### Task 7: Record the Whole Transcript

**Files:**
- Modify: `kernel/src/Lips/Generate/PiJson.hs`
- Modify: `kernel/src/Lips/Generate/Record.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `PiReply` gains `prTranscript :: Text` — every message in the terminal `agent_end` event rendered as `role: …` blocks, including `toolCall`/`toolResult` entries with their arguments and output, each result truncated at 4000 characters with a trailing `… [truncated, N characters elided]`.
- `record :: Text -> Target -> Double -> Int -> Text -> Text -> Text -> Text -> Text` — model, target, confidence, rounds, system prompt, program corpus, transcript, reply.

- [ ] **Step 1: Write the failing test**

```haskell
    it "recovers tool calls and their results from the stream" $ do
      let ev = "{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"toolCall\",\"name\":\"lips_options\",\"arguments\":{\"query\":\"services.restic\"}}]},{\"role\":\"toolResult\",\"content\":[{\"type\":\"text\",\"text\":\"services.restic.backups.<name>.paths : list of string\"}]}]}"
      prTranscript (parsePiReply ev) `shouldSatisfy` T.isInfixOf "lips_options"
      prTranscript (parsePiReply ev) `shouldSatisfy` T.isInfixOf "list of string"
```

Confirm the real event shape first by running one mint with `--mode json` and reading a captured stream; adapt the fixture to the actual field names rather than the guess above.

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Implement `prTranscript`** by walking the `agent_end` messages in order and rendering each content item; truncate long text with the marker.

- [ ] **Step 4: Write it into the record**

In `Record.record`, add sections in this order: `model`, `target`, `confidence-threshold`, `rounds`, `--- system prompt ---`, `--- program (input) ---`, `--- transcript ---`, `--- raw reply ---`.

- [ ] **Step 5: Verify**

Run a mint, then confirm the stamp still re-hashes:

```bash
just generate examples/ledger.backup.lips
head -1 examples/backup/backup.lang        # @gen:<id>
```
and that `<id>` equals `genId` of the written `.generation` (the existing suite test that pins this must be updated to the new record shape).

- [ ] **Step 6: Commit**

```bash
git commit -am "record: pin the whole mint transcript, tool calls and results included"
```

---

### Task 8: Docs

**Files:**
- Modify: `README.md`, `DESIGN.md` (§13 ledger), `kernel/README.md`, `TODO.md`, `justfile`

- [ ] **Step 1: README** — in "Generate (once, AI)", say the mint may look up options and rehearse its engine against the real gate, within `--rounds` (default 8), and that everything it saw is recorded.
- [ ] **Step 2: DESIGN §13** — add a Done entry: the mint is a bounded verifying loop; name `Lips.Generate.Gate`, the two verbs, the extension, and the transcript record.
- [ ] **Step 3: kernel/README.md** — add `Lips/Generate/Gate.hs` to the module map.
- [ ] **Step 4: TODO.md** — note that the gap-report item (2) now has a natural producer.
- [ ] **Step 5: justfile** — add `options query` and `dry-run` recipes mirroring `generate`.
- [ ] **Step 6: Commit**

```bash
git commit -am "docs: the mint is a bounded verifying loop with two tools"
```

## Self-Review

- Spec coverage: schema tool (Task 2), dry-run tool with the full gate (Tasks 1, 3), extension exposing exactly two tools (Task 5), hermetic pi invocation (Task 6), integer `--rounds` default 8 known to the model and enforced by the tool (Tasks 4, 5), whole-transcript provenance (Task 7).
- The dry-run's expect stage uses the committed `.expect` when present and none otherwise, matching `generate`'s first-mint bootstrap; stated in Task 3 and in the tool description.
- Names used consistently: `queryOptions`, `dryRunVerb`, `promptWithBudget`, `MintEnv`, `prTranscript`, `stepBudget`.
</content>
