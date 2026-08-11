# The Answer Is A Submitted Draft — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A mint cannot answer with a draft it never checked, because the checked draft IS the answer: `check_draft` becomes `submit_draft`, the last clean submission is the engine lips takes, and the model's free-text reply stops carrying engine lines at all.

**Architecture:** One new one-way channel from the tool to `generate`. `generate` owns a temp directory and passes `LIPS_MINT_ANSWER=<dir>/answer` into the pi child's environment; `submit_draft` runs the same `lips check --draft` loop `check_draft` runs today and, when every program passes, writes the draft bytes to that path (overwriting an earlier clean submission). After pi exits, `generate` reads the file instead of parsing the text reply for engine lines: a missing file is a refusal naming the remedy, a present one is the reply, entering the record's `--- reply ---` section and `genId` exactly as the text reply does today. The gate that decides still runs once, in Haskell, over the submitted draft — the full accept path including what `--draft` cannot run (claim gate, artifact build).

**Tech Stack:** Haskell (GHC, base+containers+text+aeson+optparse-applicative), hspec conformance suite, one TypeScript pi extension (`assets/mint-tools.ts`), the mint prompt (`assets/mint/body.md`).

**Design (in lieu of a spec — the measurement and the rejected alternative):**

- Observed twice on 2026-08-09 (TODO item 1): a mint ran `check_draft` over draft A and answered with a different draft B, so lips refused B a minute later with the exact message the tool had already shown, and the whole call was wasted. The prompt already pleads ("answer with those lines ALONE"); invariant 2 asks for a guard.
- REJECTED: the fingerprint gate (TODO's original sketch — the tool records a hash of every draft it validates, `generate` refuses a reply hashing to nothing recorded). It cannot save the call: `pi -p` is one-shot, so by the time `generate` compares hashes the model is gone. A bad unchecked reply is refused by the existing gates anyway; a sound unchecked reply would be refused for process reasons alone, a pure loss. The refusal is better-worded, and nothing else.
- CHOSEN: last clean submission wins. The fingerprint gate's only sound completion is "fall back to the checked draft when the reply differs" — at which point the reply is dead weight and the design should say so. Making submission the answer turns the observed waste into an in-call retry (a refused submission returns the gate's words to a model that is still alive and can fix and resubmit) and deletes two prompt pleas structurally: "answer with engine lines only, never narrate" (the text reply is inert now — a narrating sentence can no longer fail a mint) and "answer with what you checked" (identity by construction). The two open questions under the old sketch (normalizing whitespace for the hash comparison; a first mint checked in pieces) dissolve: there is no comparison, and only a complete clean draft stages.
- What does NOT move: who judges. `submit_draft` REPORTS and stages; the accept gates still run in Haskell after pi exits, over the staged bytes, including the gates `--draft` cannot run. A model that never submits is refused — that is new (today a sound unchecked reply passes), and it is the point: the tool loop is where a defect is cheap, and the protocol now has exactly one door.
- Invariant 6 holds unchanged: the submitted draft is the recorded reply (hashed into `genId`), and every submission attempt is a tool call in the transcript, which is hashed too.

## Global Constraints

- The suite and app stay `-Wall` clean.
- Fast test: from `kernel/`, `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/b -o /tmp/spec && /tmp/spec`. The app builds separately: `ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/bapp -o /tmp/lips` (Spec does not import `app/Main.hs`).
- Full: `nix flake check`, the check-expect loop (`for p in examples/*.lips; do nix run . -- check "$p"; done`), and `XDG_RUNTIME_DIR=/tmp just test-draft`.
- Nix flakes see only git-tracked files: `git add` before any `nix build`/`nix run`.
- Worktree under `.worktrees/`, small single-line commits, rebase + ff-merge, no merge commits, no co-author lines.
- The kernel (`Lips.Kernel.*`) is not touched at all. Every change is in `app/Main.hs`, `Lips.Report`, `assets/mint-tools.ts` and `assets/mint/body.md`.
- Committed engines, records and the reply FORMAT are untouched: `parseEngineCandidates` reads the submitted bytes exactly as it read the text reply, so every committed example keeps checking and compiling byte-identically.
- Comments explain why, referring only to current code.

---

### Task 0: Worktree and Baseline

- [ ] **Step 1:** `git worktree add .worktrees/submit-draft -b submit-draft`, work there.
- [ ] **Step 2:** From `kernel/`, run the fast test and note the baseline count (838 examples, 0 failures at plan time); build the app.

---

### Task 1: `generate` Reads the Answer From the Staged File

The Haskell half first, because it defines the contract the tool writes to. `callPi` (grep it in `app/Main.hs`) gains the answer path; the reply source moves from `prReply` to the file.

**Files:**
- Modify: `kernel/app/Main.hs` (`callPi`: create a temp dir, pass `LIPS_MINT_ANSWER` in `ours`, read the file after `ExitSuccess`)
- Modify: `kernel/src/Lips/Report.hs` (the two new refusal texts, pure, beside their siblings)
- Test: `kernel/test/Spec.hs` (the `Lips.Report` describe-block)

**Interfaces:**

```haskell
-- Report.hs
noSubmission  :: Text  -- pi exited clean but the answer file does not exist:
                       -- "the mint never submitted a clean draft" naming
                       -- submit_draft and "run generate again" as the remedy.
emptySubmission :: Text -- the file exists with no bytes: a tool defect, not a
                        -- model defect; name the extension.
```

In `callPi`: `withSystemTempDirectory "lips-mint"` around the pi run; the path `<dir>/answer` goes into `ours` as `LIPS_MINT_ANSWER`; on `ExitSuccess`, `doesFileExist` then `TIO.readFile` replaces the `prReply` value (the parsed `prModel`/`prTranscript` stay). The old "returned no usable reply" branch becomes the `noSubmission` refusal. `prReply` itself stays parsed and recorded in the transcript stream — it is provenance, no longer input.

- [ ] **Step 1: Write the failing tests** (wordings only; the IO seam is exercised by `just test-draft` in Task 4):

```haskell
it "a mint that never submitted is refused naming the tool and the remedy" $ do
  noSubmission `shouldSatisfy` T.isInfixOf "submit_draft"
  noSubmission `shouldSatisfy` T.isInfixOf "generate"
```

- [ ] **Step 2:** Run; failures.
- [ ] **Step 3:** Implement; app builds `-Wall` clean. Comment on the temp dir: absence of the file is the signal, so `generate` creates the DIRECTORY and never the file.
- [ ] **Step 4:** Suite green.
- [ ] **Step 5:** Commit: `generate: the reply is the staged submission, so an unchecked answer cannot exist`

---

### Task 2: `check_draft` Becomes `submit_draft`

**Files:**
- Modify: `assets/mint-tools.ts`

- [ ] **Step 1:** Rename the tool to `submit_draft`; `required("LIPS_MINT_ANSWER")` at load beside the others (fail at load, not per call — same reasoning as the existing comment). The execute loop is unchanged; after the last program passes, write `params.draft` to the answer path (overwrite: the last clean submission is the answer, stated in a comment). Update both message texts: the failure text keeps the gate's words; the success text becomes "staged as your answer — the last clean submission is the engine lips takes; your final text reply is not read for engine lines" (this replaces the "answer with those lines ALONE" plea, which Task 1 made unnecessary).
- [ ] **Step 2:** No test harness exists for the extension (noted in self-review); the live witness is Task 4.
- [ ] **Step 3:** Commit: `mint tools: a clean draft is submitted, and the last submission is the answer`

---

### Task 3: The Prompt Stops Pleading

**Files:**
- Modify: `assets/mint/body.md` (the `check_draft(draft)` paragraph, grep it; the Self-Review Checklist preamble "Before you answer")

- [ ] **Step 1:** Rewrite the tool paragraph for `submit_draft`: call it with the complete engine when you believe it is done; a refusal names the gate in the words lips uses, fix and submit again; the last clean submission is your answer, and nothing you write outside the tool is read as engine lines. Delete the "never narrate" instruction wherever it appears (it guarded the text reply, which no longer carries the engine). Keep "a clean submission is not a guarantee of acceptance" — the claim gate and artifact build still run after.
- [ ] **Step 2:** Run the 21 writing rules over the new prose.
- [ ] **Step 3:** Commit: `mint prompt: the answer protocol is submit_draft, and the narration plea dies with the text reply`

---

### Task 4: The Draft Door Witnesses the Staging

`just test-draft` already drives `lips check --draft` directly; add the staging seam it cannot see any other way, shell-level like its siblings.

**Files:**
- Modify: `justfile` (`test-draft` recipe)

- [ ] **Step 1:** Append one scenario: export `LIPS_MINT_ANSWER="$tmp/answer"`, run a clean draft through `check --draft` — assert the file does NOT appear (the VERB reports; only the TOOL stages, so the verb must stay side-effect free for `just test-draft` itself and for humans). This pins the boundary: staging lives in `mint-tools.ts`, never in the verb.
- [ ] **Step 2:** `XDG_RUNTIME_DIR=/tmp just test-draft` — OK.
- [ ] **Step 3:** Commit: `test-draft: the draft verb stays side-effect free; staging is the tool's alone`

---

### Task 5: Live Mint, Docs, Ledger

- [ ] **Step 1:** One live re-mint of a small example (`examples/greet.lips` or the cheapest current candidate) to witness the protocol end to end: the transcript must show `submit_draft`, the record's reply section must equal the staged draft, and check/compile must stay green. If the model narrates after submitting, nothing fails — that is the point; note it in the ledger entry if observed.
- [ ] **Step 2:** `README.md`: the generate section's tool sentence names `submit_draft`; `DESIGN.md` §13: new Done entry (what was observed, why the fingerprint gate was rejected, what the submission channel is); `TODO.md`: item 1 closes (drop it, per the file's own header).
- [ ] **Step 3:** Full verification: fast test, app build, `nix flake check`, check-expect loop, `XDG_RUNTIME_DIR=/tmp just test-draft`.
- [ ] **Step 4:** Commit: `docs: the answer is a submitted draft lands in README, ledger and TODO`
- [ ] **Step 5:** Finish: rebase on main, ff-merge, delete the worktree (finishing-a-development-branch skill).

## Self-Review Notes

- The extension has no test harness; its behavior is witnessed by the live mint (Task 5) and bounded by the verb-side test (Task 4). Acceptable because the TS is deliberately dumb plumbing — the judge is the binary on both sides.
- A model that submits clean draft A, then submits failing draft B, then stops: A stands (B staged nothing), which is the stated semantics. A model that submits nothing is refused loud (Task 1) — the one behavior this plan makes stricter, deliberately.
- Multi-world and multi-program mints need nothing: the tool's program loop and the `@world` tags pass through unchanged; the staged bytes are the same reply format `parseEngineCandidates` already reads.
- Records and examples: no committed byte changes shape; the reply section's PROVENANCE changes (staged file, not stdout), its format does not.
