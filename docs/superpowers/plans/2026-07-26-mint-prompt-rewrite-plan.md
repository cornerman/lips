# Mint Prompt Rewrite Implementation Plan (Plan C of three)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the accreted mint prompt with one written for the agent that actually does the job: it explains where the agent sits in lips, how the machine it programs executes an engine, how to verify its own work with the two tools, what it may say, and how to review itself — with examples the conformance suite keeps true.

**Architecture:** The prompt stops being escaped Haskell string literals and becomes markdown under `assets/mint/`, embedded into the binary at compile time with `file-embed`. `Lips.Generate.Minting` keeps its public surface (`systemPromptFor`, `systemPrompt`, `promptWithDirection`, plus Plan A's `promptWithBudget`) and merely composes embedded documents. The rewrite lands in two moves: a byte-identical migration (no wording change, so any regression is provably mechanical), then the new text section by section. A new suite test extracts every fenced example block marked `lips-engine` from the prompt and requires the kernel to parse it, so a teaching example cannot outlive the grammar it teaches.

**Tech Stack:** Haskell (GHC, `-Wall` clean), `file-embed`, `hspec`, Nix flakes.

## Global Constraints

- The kernel knows nothing: the prompt may name option namespaces of the target world (that is the world preamble's job) and must otherwise stay domain-blind. Examples use invented, neutral domains, never a real repo engine, so no mint inherits restic or nginx as a default.
- Deduce-or-fail stays a top-priority directive in the prompt (DESIGN §189: "the generator agent's operating prompt carries deduce-or-fail as a top-priority, non-negotiable directive").
- Invariant 4: the prompt never teaches a workaround. Where the grammar cannot express something, the instruction is to file a gap (Plan B), not to improvise.
- The prompt is a versioned artifact pinned into `.generation` and `genId`; changing it changes every future stamp, which is expected and must be noted in the DESIGN ledger entry.
- Examples in the prompt must parse: the suite enforces it.
- The suite and app stay `-Wall` clean. Worktree `.worktrees/mint-prompt`, branch `feat/mint-prompt`.
- Sequenced after Plans A and B, whose tools and block kinds the new text describes.

## File Structure

- Create `assets/mint/body.md` — the world-neutral body (everything below the world preamble).
- Create `assets/mint/nixos.md`, `assets/mint/home-manager.md` — the two world preambles, replacing `worldSection`.
- Create `assets/mint/direction.md` — the advisory-direction wrapper text, replacing the inline `T.unlines` in `promptWithDirection`.
- Modify `kernel/src/Lips/Generate/Minting.hs` — embed and compose; delete the string literals.
- Modify `flake.nix` — add `file-embed` to the GHC package set; the assets must be visible to the build (they are, `cp -r ${./kernel}` becomes `cp -r ${./.}` or the assets are copied explicitly — see Task 1 Step 3).
- Modify `kernel/test/Spec.hs` — keep the pinned-clause test (updated clauses), add the example-block parse test.
- Modify `README.md`, `DESIGN.md` (§13), `kernel/README.md`.

---

### Task 1: Migrate the Prompt to Embedded Markdown, Byte for Byte

**Files:**
- Create: `assets/mint/body.md`, `assets/mint/nixos.md`, `assets/mint/home-manager.md`, `assets/mint/direction.md`
- Modify: `kernel/src/Lips/Generate/Minting.hs`, `flake.nix`
- Test: `kernel/test/Spec.hs` (existing clause test must still pass unchanged)

**Interfaces:**
- Unchanged public surface: `systemPrompt :: Text`, `systemPromptFor :: Target -> Text`, `promptWithDirection :: Maybe Text -> Target -> Text`.
- New private: `bodyDoc, nixosDoc, homeManagerDoc, directionDoc :: Text` via `Data.FileEmbed.embedStringFile`.

- [ ] **Step 1: Extract the current text verbatim**

Write a throwaway program that prints `systemPromptFor Nixos` and `systemPromptFor HomeManager`, and split the output into the world preamble and the shared body exactly at today's boundary. Save them as `assets/mint/nixos.md`, `assets/mint/home-manager.md`, `assets/mint/body.md`. Do not fix a single word yet.

- [ ] **Step 2: Embed them**

```haskell
{-# LANGUAGE TemplateHaskell #-}

import Data.FileEmbed (embedStringFile)

-- The prompt is prose, so it lives as prose: markdown files under assets/mint,
-- embedded at compile time. Escaped string literals made every example in it
-- expensive to write and hard to read, which is how the old prompt accreted
-- three wordings of the same prohibition. Embedding keeps the binary
-- self-contained, so provenance is unaffected: the record still stores the
-- exact text the model saw.
bodyDoc :: Text
bodyDoc = T.pack $(embedStringFile "../assets/mint/body.md")
```

Resolve the relative path against the GHC invocation's working directory; if that proves brittle, copy the assets into `kernel/assets/mint/` during the build and embed `"assets/mint/body.md"`. Decide once and note the choice in the module header.

- [ ] **Step 3: Make the build see the assets**

In `flake.nix`, add `p.file-embed` to `ghc`, and ensure the assets are present where the compile runs:

```bash
  cp -r ${./kernel}/. build && mkdir -p build/assets && cp -r ${./assets}/. build/assets && cd build
```

Apply the same change to the `checks.kernel-tests` derivation.

- [ ] **Step 4: Prove the migration changed nothing**

Run the suite (`the generate prompt is a pinned artifact` test must pass untouched), then diff the rendered prompt against a copy captured before the change:

```bash
cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/o -o /tmp/lips
diff <(cat /tmp/prompt-before.txt) <(/tmp/print-prompt)
```
Expected: empty diff.

- [ ] **Step 5: Commit**

```bash
git add assets/mint kernel/src/Lips/Generate/Minting.hs flake.nix
git commit -m "mint: move the prompt into embedded markdown, byte for byte"
```

---

### Task 2: The Example-Block Guard

**Files:**
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- The prompt marks every engine example as a fenced block with the info string `lips-engine`. The test extracts each such block and runs `parseEngineCandidates` over it, requiring no errors.

- [ ] **Step 1: Write the test**

```haskell
  -- Examples teach the grammar, so a stale one teaches a grammar that no longer
  -- exists. Extract every ```lips-engine block from the prompt and require the
  -- real parser to accept it: an example cannot outlive the syntax it shows.
  describe "prompt examples stay parseable" $
    it "every lips-engine block in the prompt parses" $ do
      let blocks = fencedBlocks "lips-engine" systemPrompt
      blocks `shouldSatisfy` (not . null)
      mapM_ (\b -> fst (parseEngineCandidates b) `shouldBe` []) blocks
```

with the helper beside it:

```haskell
-- | The bodies of ```<tag> … ``` fenced blocks, in order.
fencedBlocks :: Text -> Text -> [Text]
fencedBlocks tag = go . T.lines
  where
    go ls = case break (== "```" <> tag) ls of
      (_, [])        -> []
      (_, _ : rest)  -> let (body, rest') = break (== "```") rest
                        in T.unlines body : go (drop 1 rest')
```

- [ ] **Step 2: Run it**

Expected: FAIL at first, because today's examples are prose-indented, not fenced. Convert the existing examples in `assets/mint/body.md` into ```` ```lips-engine ```` blocks and fix any that no longer parse (each such fix is a real bug the guard just caught — record it in the commit message).

- [ ] **Step 3: Commit**

```bash
git commit -am "test: every engine example in the mint prompt must parse"
```

---

### Task 3: Rewrite the Body

**Files:**
- Modify: `assets/mint/body.md`
- Modify: `kernel/test/Spec.hs` (the pinned-clause list)

This is the substance. Write the document in the order below; each section is one commit, so a reviewer can reject one section without rejecting the rewrite. Keep the existing rules' *content* — none of them is wrong — but state each exactly once, in the section that owns it, and give the agent the model of the machine it is programming, which today it lacks entirely.

House style for the document: short paragraphs, second person, no bullet lists where a sentence works, every prohibition immediately followed by the correct form. Length is not the enemy; repetition is.

- [ ] **Step 1: Section 1, "Where You Are"**

Content requirements: lips shrinks the human-reviewed artifact to a few plain lines; the human owns only the `.lips` program; you mint the engine once and are then gone forever; from then on `compile` reads the same program with your patterns, deterministically and offline, with no model; a value the human later edits must flow through without you, which is why every program value becomes a hole; a line your patterns cannot read fails loud and sends the human back to `generate`, which costs them a mint. Name the artifacts the human will read afterwards: `<language>.lang`, `README.md` (your report), `<language>.expect`.

Keep the load-bearing sentences "You act exactly once" and "replace EVERY program value with a hole".

Commit: `mint prompt: open with the agent's situation, not the output syntax`.

- [ ] **Step 2: Section 2, "The Machine You Program"**

Content requirements, the pipeline end to end, in the kernel's own terms:

1. A program is a list of lines. Crystallization matches each line against exactly one pattern; an unmatched line and an ambiguously matched line both fail.
2. A match emits one or more decisions, each `id kind subject "assertion" @provenance`. The subject vocabulary is yours to invent; it is the interface between your patterns and your rules.
3. Refinement merges decisions; two decisions on one subject with different assertions is a conflict and fails.
4. Rules map `kind subject` to option emits. Every decision must be mapped, except `concept`.
5. Emitted values are the closed value grammar: no computation exists, by construction — there is no constructor for it.
6. `<self>` binds to the program's instance name at realize time; a `<capture>` segment binds per item and fans one rule out across an `attrsOf`; a rule emitting a list makes its subject aggregate across lines.
7. Realization renders a NixOS module; lips parses it with `nix-instantiate --parse`, checks every option path and type against the pinned schema, and evaluates the module to test the expects.

State plainly that each numbered stage is a place your engine can fail, and that `lips_dry_run` reports failures in exactly these terms.

Commit: `mint prompt: describe the machine the engine drives, stage by stage`.

- [ ] **Step 3: Section 3, "How You Work"**

Content requirements: draft the engine, then use the tools; `lips_options` to confirm every option path and type before you rely on memory; `lips_dry_run` to rehearse the whole gate; read the verdict, fix, repeat; the budget (Plan A) and that each result reports what remains; spend the last call verifying the exact text you will answer with; artifact sources are not staged in a rehearsal, so an artifact build is only exercised by the real gate; when the loop will not converge, do not improvise — answer with your best engine and a `gap` block.

Commit: `mint prompt: teach the verify-and-iterate loop and its budget`.

- [ ] **Step 4: Section 4, "What You May Say"**

Content requirements: the final message is items only, in the six line forms plus three block forms, no prose outside blocks; confidence is always token 1; ids pair a `because` note to its item; the `report` block is required, exactly one, and is what the human reads (say what the language reads, the vocabulary and why, the mechanism chosen and what was rejected, every value you had to invent, and what a program in this language must state); a `gap` block files a missing kernel capability with the line it blocks and a minimal repro; the final message must be exactly the engine text you last dry-ran green, plus report and gaps.

Keep the grammar table from the current prompt verbatim in a fenced block, extended with `report` and `gap`.

Commit: `mint prompt: state the output contract once, including report and gap`.

- [ ] **Step 5: Section 5, the construct reference**

One subsection per construct, each with a ```` ```lips-engine ```` example: patterns and holes (including quoted holes and bulleted items); kinds, with `concept` and why it needs no rule; subjects and orthogonality; generalizing across several programs; rules and the value grammar; typed holes; package holes; `<self>`; `<capture>`; list aggregation; artifacts and source blocks; demands; expects, including the derivation prohibition.

Rule for this section: each prohibition appears in exactly one subsection, and immediately shows the correct form. The current prompt's triple statement of "never `${pkgs.<hole>}`" collapses into one place, in the package-hole subsection.

Commit: `mint prompt: one reference subsection per construct, each prohibition stated once`.

- [ ] **Step 6: Section 6, "Designing a Good Language"**

Content requirements: hole everything a human might edit and nothing else; patterns must be orthogonal; a heading plus its items share a subject prefix; prefer a demand over an invention when the program is merely silent; lower confidence rather than invent a free choice, and pair it with a `because`; the vocabulary is the human's future writing surface, so name subjects the way the domain talks; on a regeneration, keep the previous vocabulary unless something forces a change, and say in the report what moved and why (the previous engine, report and contract are appended to your input when they exist, and they are context, never evidence — the programs remain the only truth).

Commit: `mint prompt: guidance on what makes a language worth living with`.

- [ ] **Step 7: Section 7, two worked examples**

Two complete passes in neutral invented domains, each showing program lines, the full engine, and one sentence on what the human gets: (a) a configuration-only language with a heading and a bulleted list, exercising patterns, subjects, typed holes, `<self>`, aggregation, demands and expects; (b) a language whose program must be built from source, exercising an artifact, a source block, and the no-expect-for-a-derivation rule.

Both must pass the Task 2 guard.

Commit: `mint prompt: two verified worked examples, end to end`.

- [ ] **Step 8: Section 8, the self-review checklist**

A short numbered list the agent runs before answering: every line of every program matched by exactly one pattern; every decision mapped or a `concept`; every program value a hole; every option path confirmed with `lips_options`; every expect naming a value option, never a derivation; the last dry-run green and matching the text you are about to send; the report written; every invented value either demanded, low-confidence with a because, or named in the report.

Commit: `mint prompt: a self-review checklist before the final answer`.

- [ ] **Step 9: Update the pinned-clause test**

Rewrite the clause list in `kernel/test/Spec.hs`'s "generate prompt is a pinned artifact" test to the new load-bearing sentences (keep `act exactly once`, `replace EVERY program value with a hole`, `refusal beats invention`; add `lips_dry_run`, `report block`, `gap`, and the section titles). Run the suite.

Commit: `test: pin the rewritten prompt's load-bearing clauses`.

---

### Task 4: World Preambles and Direction Wrapper

**Files:**
- Modify: `assets/mint/nixos.md`, `assets/mint/home-manager.md`, `assets/mint/direction.md`

- [ ] **Step 1:** Rewrite each preamble to say what the world *is* (a whole machine as root; one user's `$HOME`, unprivileged), which namespaces belong to it, what `<self>` keys there, and that `lips_options --target <world>` searches exactly this world's schema.
- [ ] **Step 2:** Keep the direction wrapper's two load-bearing sentences ("PREFERENCE, not requirement", "never let it override a value the program states"), which the suite pins.
- [ ] **Step 3:** Run the suite; the home-manager clause test must still pass.
- [ ] **Step 4: Commit**

```bash
git commit -am "mint prompt: rewrite the world preambles around what each world is"
```

---

### Task 5: End-to-End Verification and Docs

**Files:** `README.md`, `DESIGN.md` (§13), `kernel/README.md`

- [ ] **Step 1: Re-mint every example**

```bash
git add . && for p in examples/*.lips; do nix run . -- generate --renew "$p" || echo "FAILED $p"; done
just check-expect
```
Expected: every example mints and its contract holds. Any language that now needs more rounds than the default is a finding: record it in the DESIGN entry rather than raising the default silently.

- [ ] **Step 2: DESIGN §13** — Done entry: the prompt is an embedded, example-verified document; note that every future `@gen` stamp changes because the prompt is part of `genId`.
- [ ] **Step 3: README** — one sentence in "Generate (once, AI)" that the mint's instructions live in `assets/mint/` and are reviewable.
- [ ] **Step 4: kernel/README.md** — note that `Lips.Generate.Minting` composes embedded documents.
- [ ] **Step 5: Commit**

```bash
git commit -am "docs: the mint prompt is a reviewable, example-verified document"
```

## Self-Review

- Spec coverage: markdown assets embedded with `file-embed` (Task 1), verified examples (Tasks 2, 3 Step 7), big-picture opening (Task 3 Step 1), the machine model that lets the agent reason instead of pattern-match (Step 2), the tool loop and budget (Step 3), output contract including Plan B's blocks (Step 4), per-construct reference with each prohibition stated once (Step 5), design guidance and regeneration stability (Step 6), self-review checklist (Step 8), world preambles (Task 4).
- The rewrite is split so a reviewer can reject one section; the migration is byte-identical first, so wording changes are never entangled with mechanism changes.
- Names used consistently: `bodyDoc`, `nixosDoc`, `homeManagerDoc`, `directionDoc`, `fencedBlocks`, block tag `lips-engine`.
</content>
