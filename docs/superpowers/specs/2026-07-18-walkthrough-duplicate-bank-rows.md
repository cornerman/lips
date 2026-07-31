# Walk-Through: Duplicate Bank Rows

Companion to `DESIGN.md` (spec v2), executing phase 2 of
its plan: one feature traced end-to-end through the generate/run loop, every
stage written as a decision base. This document doubles as the first draft of
the canonical text form; the form's extracted rules close the document.

The scenario: a personal ledger ingesting bank CSV files. Reality misbehaves
in a known way (banks resend rows), and the walk-through shows how the
misbehavior is absorbed by the engine without the Solution ever containing a
workaround.

## t0: The Program

The human writes a file, `ledger`. Five lines, loose text, no keywords
required:

    a ledger for my accounts.
    the bank drops csv files into inbox/, daily.
    every bank row becomes a transaction: money moves on a date, with a note, into an account.
    an account's balance is the sum of its transactions.
    `ledger balances` prints balances per account and month.

This is the whole application, and it stays roughly this size for the rest
of the document.

## t0: generate (first engine)

`lips generate` is the only step where AI runs. It must give each line a
defined meaning or ask. It produces three artifacts.

**1. The canonicalized reading** (a derived view, not an edit of the file).
Each human line becomes one decision with an id, a kind, and resolved
subjects. Provenance anchors each decision to its source line:

    d1  concept    ledger : application kinds = service + cli        [ledger:1]
    d2  fact       bank-feed : csv, location inbox/, cadence daily   [ledger:2]
    d3  oblige     bank row -> exactly one transaction               [ledger:3]
    d4  invariant  account.balance = sum(account.transactions)       [ledger:4]
    d5  view       cli "ledger balances": balance by (account,month) [ledger:5]

The reading is what review means at this level: five decisions, each
checkable against its source line by eye.

**2. Open questions.** The minted language demands decisions the program
does not contain. Guessing is not in the architecture, so generate stops
with demands:

    q1  open  what currency do amounts use?            demanded by concept money [via d3]
    q2  open  which csv columns carry date, amount,
              note, account?                           demanded by mechanism ingest [via d2,d3]

The human answers by adding facts, either as new lines in `ledger` or as
answers that become lines:

    amounts are EUR.
    inbox/2026-07-01.csv is a sample of the bank's format.

Answering q2 with a sample file is itself a fact decision; the engine
derives the column mapping from the sample deterministically and records the
derived mapping with provenance `[via q2-answer]`, where it is reviewable.

**3. The engine E1**, with its language L1 (concepts: account, transaction,
bank row, balance, period; the obligation patterns it can map) and its
mechanisms. By definition (spec Section 4), every mechanism arrives with
derived tests and fuzz targets; E1's corpus at birth covers csv parsing,
storage, balance summation, and timer scheduling.

## t0: run

`lips run ledger` refines the decision base deterministically, stage by
stage, until ground. Excerpt of the chain under d3:

    d3        oblige     bank row -> exactly one transaction         [ledger:3]
     m31      mechanism  ingest: watch inbox/, parse csv             [d3 via L1.ingest-csv]
     m32      mechanism  store: sqlite, table transactions           [d3,d4 via L1.persist]
     m33      schedule   daily                                       [d2 via L1.cadence]
      g1      ground     nixos module: systemd service ledger-ingest [m31,m33]
      g2      ground     nixos module: timer, daily                  [m33]
      g3      ground     cli package: ledger                         [d5 via L1.cli-view]

Every stage is a decision base. The owner reads the top; an auditor can walk
d3 to g1 mechanically. The realized NixOS module deploys beside hand-written
modules on an existing machine. From here on, `lips run` repeats forever
without AI.

## t1: Reality Misbehaves

The bank resends rows: yesterday's file and today's file share entries. The
owner suspects it and throws an assumption. One line added to `ledger`:

    no transaction is recorded twice, even if the bank resends a row.

The engine answers assumptions with a status (spec Section 3). E1 answers:

    a1  assume  no transaction recorded twice on resend
        status: OPEN
        counterexample: fuzz case ingest(f1); ingest(f2) where f2 repeats
        row r of f1 yields two transactions   [E1 corpus, fuzz target m31-f4]

The counterexample comes from E1's own fuzz corpus, which already contained
resent-file cases because ingest mechanisms derive fuzz targets over their
input space by definition. The assumption is open, so the program has
escaped the engine: regenerate.

## t1: generate (engine evolution)

The AI must now map a1 to a mechanism. It cannot, without one more decision,
because the obligation is ambiguous in a way no mechanism may silently
resolve: two rows that look identical might be two genuine payments (same
day, same amount, same note). Deduplication by content would silently drop
real money. Generate therefore stops with a demand instead of a guess:

    q3  open  can two distinct payments produce identical csv rows?
              demanded by obligation a1 x mechanism dedupe [via a1,d3]

The human answers with domain truth, one line:

    the bank's reference column is unique per payment.

Now the mapping is decidable. E2 differs from E1:

    meta-decisions added [via a1,q3-answer]:
      row identity = column "reference"
      ingest is an upsert keyed on reference
    tests added:
      property: ingest(f1) then ingest(f2) = ingest(f1 union f2)   (idempotence)
      property: distinct references never merge
      fuzz: resent, reordered, and interleaved files
    tests removed: none

E2 must pass E1's accumulated corpus before it replaces E1 (spec Section 5).
No stable test contradicted the change, so the removed-test set is empty and
the reviewable semantic diff is additions only. Internally the AI also
rewrote E1's storage layer while it was there; nothing above the engine can
observe that, and no one reviews it beyond the corpus.

The assumption's status flips:

    a1  status: GUARANTEED (by construction: keyed upsert)  [E2, mapping m34]

## t1: The Solution, After

The complete program:

    a ledger for my accounts.
    the bank drops csv files into inbox/, daily.
    every bank row becomes a transaction: money moves on a date, with a note, into an account.
    an account's balance is the sum of its transactions.
    `ledger balances` prints balances per account and month.
    amounts are EUR.
    inbox/2026-07-01.csv is a sample of the bank's format.
    no transaction is recorded twice, even if the bank resends a row.
    the bank's reference column is unique per payment.

Nine lines. Note what is absent: no dedupe logic, no upsert, no keys, no
retry, no file-state tracking. The duplicate-row reality is coped with
entirely below the line; the Solution gained only domain truths (a fact
about the bank) and an expectation (the assumption). This is the Heile-Welt
contract in action: the Solution is written against a world where the
invariant simply holds, and the engine earned that world.

## t2: Edits Within and Beyond the Language

**Within.** The owner changes `daily` to `hourly` in line 2. Cadence is a
parameter of L1's feed concept; E2 accepts the edited program. `lips run`
realizes a changed timer. Zero AI involved.

**Beyond.** The owner adds:

    warn me when a month's spending exceeds twice its average.

E2 rejects: L1 has no notification concept and no aggregate-comparison
pattern. Rejection is precise (it names the two missing patterns, because
failing to parse a decision is itself a decision with provenance), and the
loop returns to generate. The engine will grow alerting and the language
will grow a "warn" pattern; the corpus ratchets forward as before.

**Glue, for completeness.** No line above needed raw computation. If the
owner wanted a custom categorization nobody should generalize, it would
enter as a marked glue decision, for example:

    glue: a transaction whose note matches /REWE|EDEKA/ is category groceries, tested by grocery-spec.

Glue is one decision like any other, visibly marked, and its guarantee tier
drops from checked to tested (spec Section 7).

## What the Human Ever Read

Across the whole episode, the review surface was:

1. nine program lines (their own writing),
2. three open questions and their one-line answers,
3. one assumption status transition, OPEN with counterexample to GUARANTEED,
4. one semantic diff: "tests removed: none; guarantees added: idempotent
   ingest keyed on bank reference."

No generated code, no engine internals, no mechanism diffs. That surface is
the thesis of lips made concrete: AI did compiler-engineering volumes of
work, and the human reviewed decisions.

## Extracted: Canonical Text Form, First Draft

Rules this walk-through committed to, proposed as the starting canon:

1. **One decision per line.** A line is one assertion about named subjects.
   The file is a set: line order carries no meaning, so text diff
   approximates set diff.
2. **Loose authoring, canonical reading.** The human writes plain terse
   text. Generate assigns each line exactly one canonical reading (id, kind,
   subjects, parameters), shown in a derived read-only view. An ambiguous
   line produces an open question, never a guess.
3. **Kinds are a small closed set** (concept, fact, oblige/forbid/allow,
   invariant, view, assume, steer, glue), assigned by reading, writable
   explicitly when the author prefers.
4. **Provenance is line-anchored.** Human decisions cite file:line; derived
   decisions cite the decisions and mapping rules that produced them, all
   the way to ground.
5. **Strength defaults**: human lines outrank engine defaults; equal-strength
   contradictions are errors carrying both provenances.
6. **Questions and answers are part of the form.** Open questions are
   first-class; answers become ordinary lines. A Solution is complete when
   no demands are open.
7. **Assumptions are ordinary lines** whose statuses (guaranteed, verified,
   tested, open) are derived facts, re-answered against every engine.
8. **Glue is a marked line** carrying its own test reference; it is the only
   place computation appears in a Solution.

Open item carried forward: subject naming and cross-references between lines
(the walk-through leaned on natural phrasing; larger programs will need a
deterministic reference form), owned by the language-sketch phase.
