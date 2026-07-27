# Mint Schema Tool Implementation Plan (Plan A of three)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The mint stops guessing option names and types. During its one turn it
may look them up in the pinned schema of the target world, and everything it
looked up enters `.generation`, so what grounded the engine becomes auditable
instead of invisible training data.

**Architecture:** One shipped pi extension (`assets/mint-tools.ts`) registers
exactly one tool, `lips_options`, which shells out to a new read-only
`lips options` verb. The answer's *shape* adapts to the match set: few matches
answer as exact `path : type` leaves, many answer as a namespace breakdown ranked
by match count. `callPi` runs pi with built-in tools and ambient configuration
off, so that one tool is the only action the mint can take. The pi JSON stream's
`tool_execution_start` / `tool_execution_end` events give the transcript, which
is recorded with the reply.

**Tech Stack:** Haskell (GHC, `-Wall` clean), `optparse-applicative`, `aeson`,
`hspec`, TypeScript (one pi extension file), Nix flakes, `just`.

## Scope: What This Plan Is Not

Settled by discussion and research, recorded so none of it is re-litigated or
silently re-added.

- **Deferred to another day: the round loop.** An external loop that re-prompts
  the model with gate findings, `--max-rounds`, the `query` reply item, and the
  three-way gate verdict are all out. The reasoning, kept for whoever picks it
  up: rerunning is expensive because a fresh `pi -p` process has no memory, so
  every round re-emits the whole engine (output tokens, the costly kind) and
  triggers a fresh nix gate run. Worse, Anthropic's [prompt caching
  docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
  name the shape explicitly as a mistake: a prompt whose tail changes every
  request (findings, answers) puts the automatic breakpoint on the varying block,
  so "you pay for a fresh cache write on every request and never get a read".
  Cache writes cost 1.25x base input and reads 0.1x, so that loop is worse than
  no caching. A growing tool conversation is the opposite case, and the same doc
  lists "agentic tool use" among its target scenarios. If the loop returns, it
  returns *around* an agent that asks, not instead of one.
- **Deferred with it: extracting `Lips.Generate.Gate`.** Its only purpose was to
  let two call sites share the gate. With one call site, the extraction is
  motion without value (YAGNI). `Main.hs` keeps its staged `generate` body
  unchanged.
- **Rejected permanently: `lips dry-run` as a tool.** A rehearsal verb the model
  can call is a second call site for the gate and can therefore drift from the
  gate that commits. Ask-tools only *inform*; the gate *decides*, once, in
  Haskell, out of the model's reach. This is the durable constraint from the
  whole design discussion: informing is safe to expose, deciding is not.
- **Not now: a web route.** pi has no built-in web tool (its built-ins are
  `read`, `bash`, `edit`, `write`, `grep`, `find`, `ls`), so internet access
  would be a second `registerTool` in the file this plan creates: cheap to add
  once evidence demands it, and no evidence does yet. The known mint failure on
  record (`TODO.md`, the httpserver example refusing three decisions at
  confidence 0.35) was kernel expressiveness, not a missing world fact. Adding
  the tool channel now is what makes that future a 20-line addition.

## Why the Answer Shape Adapts (measured)

The obvious design, "return the first N matching paths alphabetically", does not
merely truncate. It **hides the answer**. Measured against the pinned NixOS
schema (24,732 options):

| Query | Matches | What a cap-40 alphabetical list shows |
| --- | --- | --- |
| `nginx` | 1,514 | `services.agorakit` only. **`services.nginx` absent.** |
| `backup` | 103 | `automysqlbackup`, `borgbackup`. **`restic` absent.** |
| `postgres` | 119 | 14 unrelated services. **`services.postgresql` absent.** |

Alphabetically earlier services that merely *mention* nginx crowd out nginx
itself, so the tool would actively mislead. Ranking *namespaces* by how many
matches each holds fixes every case on the first try: `backup` yields
`services.borgbackup (47)`, `services.restic (26)`; `nginx` yields
`services.nginx (128)` first; `postgres` yields `services.postgresql (24)` first;
`timer` yields `systemd.timers (27)`, `systemd.user (27)`.

The ranking is not a heuristic in disguise. A namespace holding many options that
match a word is the namespace *about* that thing; one or two matches means a
consumer that merely references it. Pure counting, no word list, no spelling
model, domain-blind.

## Execution Order and the One Checkpoint

Agreed before starting, so the risky parts are not entangled with the cheap ones.

1. **Tasks 1 and 2 first, then stop.** Both are pure Haskell with fast tests and
   no dependency on `nix`, `pi`, or the extension, so they land quickly and carry
   no unverified assumption.
2. **Checkpoint: a human reads real output.** Run `lips options` against the
   pinned schema and look at the actual answers before anything is built on top:

   ```bash
   nix run . -- options services.restic.backups   # expect exact leaves with types
   nix run . -- options backup                     # expect namespaces, restic among them
   nix run . -- options nginx                      # expect services.nginx ranked first
   nix run . -- options nosuchthing                # expect a clean "no match"
   ```

   The adaptive answer shape is the one decision in this plan that came from
   measurement rather than from principle (see the section above), so it gets a
   human eye at the point where changing it is still free. If the ranking reads
   badly, fix it here, not after Task 3 wires an extension around it.
3. **Tasks 3 to 7 after the checkpoint passes.** These need `nix build` and a
   real `pi` run, and they carry the plan's two unverified assumptions, both
   flagged in place: the exact spelling of pi's `--no-extensions` /
   `--no-skills` / `--no-prompt-templates` flags (Task 4), and the `result`
   encoding of the `tool_execution_end` event (Task 5). Capture one real
   `--mode json` stream and read it before writing Task 5's parser.

**Work in the worktree, never in the main tree.** On 2026-07-26 a concurrent
session editing `README.md` in the shared tree committed with `git add -A` and
swept unrelated staged work into two of its commits (`1f7bbf0`, `e834e85`),
which were pushed before it was noticed. Nothing was lost, but the messages no
longer describe their contents. The worktree is not a formality.

## Global Constraints

- The kernel is domain-blind: the new helpers are path arithmetic and counting
  over `OptionSchema` and mention no NixOS string. NixOS specifics stay in
  `Lips.Nix.Options`. (`AGENTS.md`, "The Kernel Knows Nothing".)
- Invariant 1: `compile` and `check` never call a model and never reach the tool.
  Only `generate` does.
- Invariant 2 (deduce-or-fail) is untouched. The tool removes an *excuse* for
  guessing; it does not soften any refusal. A low-confidence item and an unmet
  demand still refuse exactly as today.
- Invariant 6: whatever the model saw must enter `.generation` and be hashed by
  `genId`. A tool result the model read is such an input, so the transcript is
  not optional.
- Hermetic by explicit subtraction, matching today's `-nc` rationale (ambient
  `AGENTS.md` is excluded precisely because it would steer generation without
  entering the record): the mint's world must equal what the record pins.
- The suite and app stay `-Wall` clean.
- Nix flakes see only git-tracked files: `git add` before `nix build`/`nix run`.
- Work in a worktree under `.worktrees/mint-schema-tool`, branch
  `feat/mint-schema-tool`. Small single-line commits, rebase + ff-merge to main.
- Fast test loop from `kernel/`:
  `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`.

## File Structure

- Create `assets/mint-tools.ts` — the pi extension registering `lips_options`
  and nothing else.
- Modify `kernel/src/Lips/Kernel/OptionType.hs` — add `Answer`, `answerQuery`,
  `nearOptions`; export `dotted` and `renderOptionType`.
- Modify `kernel/src/Lips/Cli.hs` — add the `options` command.
- Modify `kernel/app/Main.hs` — the `options` verb, and rewire `callPi`.
- Modify `kernel/src/Lips/Generate/PiJson.hs` — recover the tool transcript.
- Modify `kernel/src/Lips/Generate/Record.hs` — record the transcript.
- Modify `kernel/src/Lips/Generate/Minting.hs` — state the tool in the prompt.
- Modify `flake.nix` — install the extension and bake its path.
- Modify `kernel/test/Spec.hs`, `README.md`, `DESIGN.md` (§13),
  `kernel/README.md`, `TODO.md`, `justfile`.

Dependencies: Task 1 precedes Tasks 2 and 3. Task 3 precedes Task 4. Tasks 5 and
6 are independent of 1–4. Task 7 is docs.

---

### Task 1: The Adaptive Schema Answer

**Files:**
- Modify: `kernel/src/Lips/Kernel/OptionType.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**

```haskell
-- | What a schema lookup answers with. The shape follows the match set, because
-- one shape lies: an alphabetical slice of a large match set hides the obvious
-- answer behind alphabetically earlier noise. Measured against the pinned NixOS
-- schema, "nginx" matches 1514 paths whose first 40 alphabetically are all OTHER
-- services that merely mention nginx, with services.nginx itself absent. So a
-- large match set answers with WHERE the matches live, ranked by how many each
-- namespace holds: a namespace with many matches is the one ABOUT the word, a
-- namespace with one or two merely references it.
data Answer
  = Leaves     [([Text], OptionType)]  -- ^ few enough to name exactly, with types
  | Nowhere                            -- ^ no match at all
  | Namespaces [([Text], Int)] Int     -- ^ where the matches live, heaviest
                                       --   first, plus how many namespaces the
                                       --   cap hid
  deriving (Eq, Show)

-- | Look a query up in a schema. A dotted prefix browses a namespace; anything
-- else is a substring search over the dotted paths, which is what lets a caller
-- that knows a domain word but not the namespace find it ("backup" reaches
-- services.restic.backups, because the caller chose a good word).
--
-- Grouping depth for a large match set is one segment below what was asked
-- about, floored at 2: a world's depth-1 partition is a dozen buckets and never
-- discriminates, so 2 is the shallowest informative grouping.
answerQuery :: Int -> Text -> OptionSchema -> Answer

-- | Options near a path the schema does not have. Walk the path's own prefixes
-- from longest to shortest and answer at the first one that matches something,
-- so a rule naming @services.x.backups.*.path@ is answered with the real leaves
-- under @services.x.backups@. Reuses 'answerQuery', so a wrong LEAF yields exact
-- leaves while a wrong NAMESPACE yields the breakdown: same rule, no second
-- renderer.
nearOptions :: Int -> [Text] -> OptionSchema -> Answer
```

Also export the already-private `dotted` and `renderOptionType`, which the verb
needs for rendering.

- [ ] **Step 1: Write the failing tests**

```haskell
  describe "schema lookup (what the mint may ask)" $ do
    let sch = Map.fromList
          [ (["services","restic","backups","*","paths"], OTListOf OTString)
          , (["services","restic","backups","*","repository"], OTString)
          , (["services","nginx","enable"], OTBool)
          ]
    it "a dotted prefix with few matches answers with exact leaves and types" $
      answerQuery 40 "services.restic" sch `shouldBe` Leaves
        [ (["services","restic","backups","*","paths"], OTListOf OTString)
        , (["services","restic","backups","*","repository"], OTString) ]
    it "a bare word falls back to substring search" $
      answerQuery 40 "nginx" sch `shouldBe` Leaves [(["services","nginx","enable"], OTBool)]
    -- The load-bearing case: a large match set must NOT be an alphabetical
    -- slice, or the namespace the word is about disappears.
    it "too many matches answer with the namespaces, heaviest first" $
      answerQuery 2 "services" sch `shouldBe`
        Namespaces [ (["services","restic"], 2), (["services","nginx"], 1) ] 0
    it "an unmatched query says so rather than guessing" $
      answerQuery 40 "nosuchthing" sch `shouldBe` Nowhere
    it "a wrong leaf is answered with the real leaves beside it" $
      nearOptions 40 ["services","restic","backups","*","path"] sch `shouldBe` Leaves
        [ (["services","restic","backups","*","paths"], OTListOf OTString)
        , (["services","restic","backups","*","repository"], OTString) ]
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec`
Expected: FAIL, `Variable not in scope: answerQuery`.

- [ ] **Step 3: Implement**

Match by `dotted` prefix first, substring second. When the match count is within
the cap emit `Leaves` sorted by path; otherwise group each match by its first
`max 2 (querySegments + 1)` segments, count, sort by count descending then path
ascending, take the cap, and report how many groups were hidden. Keep everything
case-sensitive: option names are lowercase-dotted by convention and the kernel
must not invent a casing rule.

- [ ] **Step 4: Run the tests.** Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/OptionType.hs kernel/test/Spec.hs
git commit -m "options: answer a schema lookup at the granularity the match set warrants"
```

---

### Task 2: The `lips options` Verb

**Files:**
- Modify: `kernel/src/Lips/Cli.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs` (parser only)

**Interfaces:**
- `Command` gains `Options OptionsOpts` with
  `data OptionsOpts = OptionsOpts { ooTarget :: Target, ooLimit :: Int, ooQuery :: String }`.
- `optionsQuery :: Target -> Int -> Text -> IO ()` in `Main`.

Rendering, which is also the tool's output, so it is written for a reader that
must decide what to ask next:

- `Leaves`: one `path : type` line each.
- `Namespaces`: `path (N options)` lines, then
  `… M more namespaces. Ask again with one of these paths to see its options.`
- `Nowhere`: `no option matches <q>` plus a line suggesting a shorter or
  differently worded query.

- [ ] **Step 1: Write the failing parser test**

```haskell
    it "options takes a target, a limit and a query" $
      parseArgs ["options", "--target", "nixos", "--limit", "10", "services.restic"]
        `shouldBe` Just (Options (OptionsOpts Nixos 10 "services.restic"))
```

- [ ] **Step 2: Run and watch it fail.** Expected: `Data constructor not in scope: Options`.

- [ ] **Step 3: Add the grammar**

```haskell
data OptionsOpts = OptionsOpts
  { ooTarget :: Target
  , ooLimit  :: Int
  , ooQuery  :: String
  } deriving (Eq, Show)

optionsOpts :: Parser OptionsOpts
optionsOpts = OptionsOpts
  <$> option targetReader
        (long "target" <> short 't' <> value defaultTarget
          <> metavar "nixos|home-manager" <> help "Which world's schema to search (default: nixos).")
  <*> option auto
        (long "limit" <> value 40 <> metavar "N" <> help "Maximum entries to print (default: 40).")
  <*> strArgument (metavar "QUERY" <> help "A dotted option prefix, or any substring of a path.")
```

and the subcommand:

```haskell
  <> command "options"
       (info (Options <$> optionsOpts)
             (progDesc "Look up option paths and types in the pinned schema. Read-only, no AI."))
```

- [ ] **Step 4: Run the test.** Expected: PASS.

- [ ] **Step 5: Implement the verb**

Reuse `ensureOptionSchema` and `parseNixOptionsJson`, then render the `Answer`.
Exit 0 even for `Nowhere`: "no match" is a valid answer to a question, not a
failure of the command. Note in the haddock that this verb is both the mint's
tool target and a human's lookup, and that it never calls a model.

- [ ] **Step 6: Verify by hand**

```bash
nix run . -- options services.restic.backups     # exact leaves with types
nix run . -- options backup                       # namespaces, restic among them
nix run . -- options nginx                        # services.nginx ranked first
```

- [ ] **Step 7: Commit**

```bash
git add kernel/src/Lips/Cli.hs kernel/app/Main.hs kernel/test/Spec.hs
git commit -m "cli: add lips options, the schema lookup behind the mint's tool"
```

---

### Task 3: The pi Extension

**Files:**
- Create: `assets/mint-tools.ts`
- Modify: `flake.nix`

**Interfaces:**
- Consumes env: `LIPS_BIN` (absolute path to the lips binary),
  `LIPS_MINT_TARGET` (`nixos` | `home-manager`).
- Registers exactly one tool: `lips_options({ query })`.

The real pi API (verified against `docs/extensions.md`): a default-exported
factory taking `ExtensionAPI`, `parameters` as a TypeBox schema, and
`execute(toolCallId, params, signal, onUpdate, ctx)` returning
`{ content: [{ type: "text", text }], details: {} }`.

- [ ] **Step 1: Write the extension**

```typescript
// The ONLY action a lips mint may take. pi runs the mint with built-in tools and
// ambient configuration disabled, so this file is the mint's complete world:
// look up an option in the pinned schema of the target world. It shells out to
// the lips binary, so what the model is told is what lips itself would say.
//
// There is deliberately no tool that JUDGES an engine. Informing is safe to
// expose; deciding is not, and the gate that decides runs once, in Haskell,
// after the model is done.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawnSync } from "node:child_process";

const bin = process.env.LIPS_BIN ?? "lips";
const target = process.env.LIPS_MINT_TARGET ?? "nixos";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "lips_options",
    label: "Options",
    description:
      "Look up option paths and their types in the pinned schema of the target " +
      "world. QUERY is a dotted prefix (browse a namespace) or any substring of " +
      "a path (find the namespace from a domain word, e.g. 'backup'). A narrow " +
      "query answers with exact 'path : type' lines; a broad one answers with the " +
      "namespaces holding the matches, the one with the most matches first, which " +
      "you then ask about by name. Every option your rules name must appear here, " +
      "or the mint is rejected.",
    parameters: Type.Object({
      query: Type.String({ description: "A dotted option prefix, or any substring of a path." }),
    }),
    async execute(_toolCallId, params: { query: string }) {
      const r = spawnSync(bin, ["options", "--target", target, params.query], {
        encoding: "utf8",
      });
      const text = [r.stdout ?? "", r.stderr ?? ""].filter(Boolean).join("\n");
      return { content: [{ type: "text", text: text || "no output" }], details: {} };
    },
  });
}
```

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
git commit -m "mint: ship the pi extension exposing exactly one schema lookup tool"
```

---

### Task 4: Rewire `callPi`

**Files:**
- Modify: `kernel/app/Main.hs`

**Interfaces:**
- `callPi :: Maybe String -> Text -> Text -> Target -> IO (Text, Text, Text)` —
  reply, model, and transcript.

- [ ] **Step 1: Change the invocation**

Replace `-nt` (all tools off) with `-nbt` (built-ins off, extension tools kept)
and load the extension, keeping the hermetic subtraction explicit:

```haskell
  toolsPath <- lookupEnv "LIPS_MINT_TOOLS"
  extArgs <- case toolsPath of
    Just p  -> pure ["-e", p]
    Nothing -> die (report
      "lips can't run the mint: its tool extension is not installed."
      ["LIPS_MINT_TOOLS is unset."]
      "\226\134\146 run the packaged lips: nix run . -- generate <program>")
```

```haskell
    -- Hermetic by explicit subtraction: -nbt drops pi's built-in tools (read,
    -- bash, edit, write, grep, find, ls -- none of which the mint may touch),
    -- --no-extensions/--no-skills/--no-prompt-templates drop whatever the user
    -- happens to have installed, -nc drops ambient AGENTS.md. What remains is the
    -- one tool this run loads on purpose, so the mint's world equals what the
    -- record pins.
    ([ "-p", "-nbt", "-nc", "--no-extensions", "--no-skills", "--no-prompt-templates"
     , "--no-session", "--mode", "json", "--system-prompt", T.unpack system ]
      ++ extArgs ++ maybe [] (\m -> ["--model", m]) mmodel)
```

Pass `LIPS_MINT_TARGET` (and inherit `LIPS_BIN`) to the child by switching from
`readProcessWithExitCode` to `readCreateProcessWithExitCode (proc "pi" args)`
with an explicit `env`.

Confirm `--no-extensions`, `--no-skills` and `--no-prompt-templates` against
`docs/usage.md` before finishing, and adapt the flag names if they differ; the
semantics above must survive any renaming.

- [ ] **Step 2: Verify end to end**

```bash
git add . && just generate examples/hello.http.lips
```
Expected: the mint still writes an engine, and pi's json stream shows
`tool_execution_start` events naming `lips_options`.

- [ ] **Step 3: Commit**

```bash
git commit -am "generate: run the mint with exactly one tool and an explicit hermetic environment"
```

---

### Task 5: Record What the Mint Looked Up

**Files:**
- Modify: `kernel/src/Lips/Generate/PiJson.hs`
- Modify: `kernel/src/Lips/Generate/Record.hs`
- Modify: `kernel/app/Main.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `PiReply` gains `prTranscript :: Text`, built from the stream's
  `tool_execution_start` (`toolCallId`, `toolName`, `args`) and
  `tool_execution_end` (`toolCallId`, `toolName`, `result`, `isError`) events,
  in stream order, each result truncated at 4000 characters with a trailing
  `… [truncated, N characters elided]`.
- `record` gains a transcript parameter, written as a `--- tool transcript ---`
  section between the program corpus and the raw reply.

Rationale to carry in the haddock: a tool result the model read is an input to
the mint, so invariant 6 requires it in the record. It is also the point of the
tool, since a lookup the model performed is evidence, where a fact it recalled
is not.

- [ ] **Step 1: Write the failing test**

```haskell
    it "recovers what the mint looked up and what it was told" $ do
      let ev = T.unlines
            [ "{\"type\":\"tool_execution_start\",\"toolCallId\":\"t1\",\"toolName\":\"lips_options\",\"args\":{\"query\":\"services.restic\"}}"
            , "{\"type\":\"tool_execution_end\",\"toolCallId\":\"t1\",\"toolName\":\"lips_options\",\"result\":\"services.restic.backups.*.paths : list of string\",\"isError\":false}"
            ]
      prTranscript (parsePiReply ev) `shouldSatisfy` T.isInfixOf "services.restic"
      prTranscript (parsePiReply ev) `shouldSatisfy` T.isInfixOf "list of string"
```

Confirm the real event shape by capturing one `--mode json` stream first and
adapt the fixture to the actual field names rather than trusting this sketch;
`docs/json.md` documents the three `tool_execution_*` events but not the exact
`result` encoding.

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Implement** `prTranscript`, walking the decoded events in order
and rendering each call and result.

- [ ] **Step 4: Write it into the record** and update the existing
`record`/`genId` tests (`kernel/test/Spec.hs:1311`) to the new arity. Keep the
header lines (`model:`, `target:`, …) first, because `readRecordedTarget` finds
the world by scanning for the first line starting with `target:`.

- [ ] **Step 5: Verify the stamp still re-hashes**

```bash
just generate examples/ledger.backup.lips
head -1 examples/backup/backup.lang        # @gen:<id>
grep -c "lips_options" examples/backup/backup.generation
```
Confirm `<id>` equals `genId` of the written `.generation`.

- [ ] **Step 6: Commit**

```bash
git commit -am "record: pin the mint's schema lookups beside its reply"
```

---

### Task 6: Tell the Model the Tool Exists

**Files:**
- Modify: `kernel/src/Lips/Generate/Minting.hs`
- Test: `kernel/test/Spec.hs`

**Interfaces:**
- `promptWithTools :: Text -> Text` in `Minting`, appended by
  `promptWithDirection`'s caller (or composed inside it, matching how the world
  preamble is composed today).

- [ ] **Step 1: Write the failing test**

```haskell
    it "the prompt names the lookup tool and when to use it" $ do
      systemPrompt `shouldSatisfy` T.isInfixOf "lips_options"
      systemPrompt `shouldSatisfy` T.isInfixOf "look it up"
```

- [ ] **Step 2: Run and watch it fail.**

- [ ] **Step 3: Implement**

Content requirements, stated once and plainly: the tool exists and searches the
pinned schema of the target world; use a dotted prefix to browse a namespace and
a domain word to find one; a broad query answers with namespaces ranked by match
count, which you then ask about by name; look up every option path and type you
are not certain of rather than recalling it, because a rule naming an option that
does not exist or has the wrong type is rejected; the tool only informs, so being
told an option exists is not permission to invent the value that fills it, and
deduce-or-fail still governs (a value the programs do not state is a demand, a
low confidence with a `because`, or nothing at all).

That last clause is the one that matters: the tool must not become a licence to
guess *values* just because *names* are now verifiable.

- [ ] **Step 4: Run the tests.** Expected: PASS. Also update the pinned-clause
list in the "generate prompt is a pinned artifact" test.

- [ ] **Step 5: Commit**

```bash
git commit -am "mint prompt: state the schema lookup tool and that it grounds names, not values"
```

---

### Task 7: Docs

**Files:** `README.md`, `DESIGN.md` (§13), `kernel/README.md`, `TODO.md`, `justfile`

- [ ] **Step 1: README** — in "Generate (once, AI)", say the mint may look up
option paths and types in the pinned schema, that this is its only tool, and that
every lookup is recorded in `.generation`.
- [ ] **Step 2: DESIGN §13** — Done entry: the mint is grounded by a schema
lookup tool. Name `answerQuery`'s adaptive granularity and why (an alphabetical
slice hides the answer), the single-tool extension, the hermetic invocation, and
the recorded transcript. Note that every future `@gen` stamp changes because the
prompt and the record shape changed. State that no tool judges an engine.
- [ ] **Step 3: kernel/README.md** — note the new `options` verb.
- [ ] **Step 4: TODO.md** — the round loop moves to the backlog with its
reasoning; the gap-report item now has a producer only once Plan B lands.
- [ ] **Step 5: justfile** — add an `options` recipe mirroring `generate`.
- [ ] **Step 6: Commit**

```bash
git commit -am "docs: the mint is grounded by one schema lookup tool"
```

## Self-Review

- Spec coverage: adaptive answer with the measured justification (Task 1), the
  verb behind it (Task 2), exactly one tool exposed (Task 3), hermetic wiring
  (Task 4), recorded lookups (Task 5), the prompt stating the tool and its limit
  (Task 6).
- Invariants: the kernel learns no NixOS name; `run`/`check` never reach the
  tool; the tool informs and never judges; deduce-or-fail is explicitly reasserted
  in the prompt so verifiable names do not license invented values; every lookup
  enters the record and `genId`.
- Deferred with reasons recorded, not dropped: the round loop, `--max-rounds`,
  the `query` reply item, `Lips.Generate.Gate`. Rejected permanently:
  `lips dry-run`.
- Names used consistently: `Answer`, `Leaves`, `Namespaces`, `Nowhere`,
  `answerQuery`, `nearOptions`, `OptionsOpts`, `optionsQuery`, `lips_options`,
  `prTranscript`, `promptWithTools`.
