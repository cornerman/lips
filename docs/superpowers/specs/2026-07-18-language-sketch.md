# Language Sketch: One Application, Three Languages

Companion to `2026-07-18-lipsidea-design.md` (spec v2), executing phase 3 of
its plan: a full application spanning three languages as one decision base,
plus the meta-decision base of one language. It also resolves the item the
walk-through carried forward: the deterministic cross-reference form.

The application continues the walk-through's ledger, grown to household
scale: record keeping (concepts, invariants, policy), ingestion (the bank
feed), and interface (CLI commands and warnings).

## The Solution

The complete program, file `ledger`. Comment lines (`#`) group for the human
eye only; the file is a set and order carries no meaning:

    a ledger for the household's money.

    # concepts
    an account holds money and has a name.
    money is EUR amounts.
    a transaction moves money into an account on a date, with a note and a category.
    a category is one of: groceries, rent, salary, transport, other.
    a budget sets a monthly EUR limit per category.

    # the bank feed
    the bank drops csv files into inbox/, hourly.
    inbox/sample.csv shows the bank's format.
    every bank row becomes exactly one transaction.
    the bank's reference column is unique per payment.
    no transaction is recorded twice, even if the bank resends a row.
    glue: a transaction's category comes from rules(note) in categories.rules, tested by category-spec; otherwise other.

    # rules of the world
    an account's balance is the sum of its transactions.
    a cleared transaction is never deleted.
    when a month's spending in a category exceeds its budget, warn on the cli at next use.

    # people
    anna and ben may read and write everything.
    the tax advisor may read everything of the past year, and change nothing.

    # interfaces
    `ledger balances` prints balances per account and month.
    `ledger budget` prints, per category, this month's spending against its budget.
    `ledger import <file>` ingests a csv by hand.

Twenty-one decisions. Every line is a domain truth, an obligation, a policy,
or an interface wish; no line is mechanism. The one computation (category
rules) is marked glue and carries its test reference, per the canonical form.

## How Three Languages Compose

At generate-time the engine reads each decision against the obligation
patterns of the languages it composes. The canonical reading (derived view)
tags each decision with the language that reads it:

    d03  concept    transaction(money, account, date, note, category)   [ledger:4]   lang: records
    d07  fact       feed bank: csv, inbox/, hourly                      [ledger:7]   lang: feed
    d09  oblige     bank row -> exactly one transaction                 [ledger:9]   lang: feed x records
    d15  invariant  account.balance = sum(account.transactions)         [ledger:14]  lang: records
    d16  forbid     delete(transaction) when cleared                    [ledger:15]  lang: records
    d17  oblige     warn(cli) when spend(month,category) > budget       [ledger:16]  lang: records x interface
    d19  policy     tax-advisor: read past-year, write nothing          [ledger:18]  lang: records
    d20  view       cli "ledger balances": balance by (account, month)  [ledger:20]  lang: interface

Three languages serve this Solution:

- **records**: entities, invariants, state rules, policies. Reused from the
  uber framework.
- **feed**: deliveries, identities, idempotence. Reused; it crystallized in
  the walk-through's problem and was promoted.
- **interface**: commands, views, warnings. Reused.

Cross-language decisions (d09, d17) are read jointly: the pattern of one
language produces the subject that the other consumes. Composition is a
merge of meta-decision bases under the kernel's ordinary merge semantics;
the engine's orthogonality check (spec Section 4) flags two languages that
claim the same pattern. Nothing about composition is special: languages are
decision bases, so composing languages IS merging sets.

What was minted fresh for this problem: nothing structural. The engine only
bound problem-specific vocabulary (category names, the budget relation) as
ordinary concepts inside `records`. The uber framework absorbed the previous
problem's work, and this Solution rode it: that is the accretion story
working as designed.

## The Meta-Decision Base of `feed`

One language, written out fully, in the same material as everything else.
This is what "the engine's language" is made of; every block below is
decisions, and the derived tooling (completion, docs, errors) is a
projection of exactly this base.

    language feed.

    # concepts it introduces
    a feed delivers rows into the system from a source, with a cadence and a format.
    a row identity decides when two rows are the same delivery.

    # demands (unmet demand = open question, verbatim)
    every feed names its source location.            else ask: where do the files arrive?
    every feed names its format or a sample file.    else ask: which format does the source use?
    an ingest under a no-duplicates expectation
      names a row identity.                          else ask: can two distinct payments produce identical rows?

    # defaults (weak decisions; any Solution line outranks them)
    cadence = daily.
    malformed rows quarantine to <feed>/rejected/, never dropped silently.
    source files are kept 90 days after ingest.

    # obligation patterns it maps (pattern -> mechanism, deterministic)
    "every <row> becomes exactly one <entity>"   -> upsert ingest keyed on row identity.
    "no <entity> recorded twice"                 -> idempotence guarantee on that ingest.
    a feed's cadence                             -> timer on the realized module.
    "<cmd> ingests a <format> by hand"           -> ingest mechanism exposed to the interface language.

    # coping strategies (Heile-Welt: reality absorbed below the line)
    resent files          -> keyed upsert; idempotent by construction.
    reordered deliveries  -> ingest is order-independent.
    partial files         -> ingest is transactional per file; half files roll back.
    source unavailable    -> retry with backoff; staleness surfaces as engine status, never as Solution concern.

    # test obligations (by definition; a mechanism without them does not lint)
    property: ingest f1 then f2 equals ingest of their union.       (idempotence)
    property: distinct row identities never merge.
    property: a rejected row appears in quarantine exactly once.
    fuzz: resent, permuted, truncated, and interleaved files.

    # guarantees it exports (what Solutions inherit; assumption answers cite these)
    exactly-once recording, given a row identity.    [by construction: keyed upsert]
    no silent data loss.                             [verified: quarantine path model-checked]
    ingestion order never changes final state.       [tested: permutation properties + fuzz]

Reading this base top to bottom is reading the language's contract: what it
lets you say (concepts, patterns), what it will ask you (demands), what it
assumes until you say otherwise (defaults), what reality it absorbs for you
(coping), and what it promises (guarantees, each tagged with its rigor tier
from spec Section 7). A vocabulary review is a review of this document, once,
by its author and audience; every Solution using `feed` inherits it.

## The Cross-Reference Form

The walk-through leaned on natural phrasing; larger programs need
deterministic reference. Rules, extending the canonical form:

1. **Introduction binds a name.** "a transaction moves money..." binds
   `transaction`. One introduction per name per Solution.
2. **References match by normalized name.** Normalization is lowercase plus
   singularization by the engine's versioned morphology table, a
   deterministic artifact like everything else: "transactions" resolves to
   `transaction`. No fuzzy matching, no synonyms unless declared.
3. **Attribute paths are possessives.** "an account's balance" is the
   attribute `balance` of `account`; chains compose ("a transaction's
   account's name").
4. **Backticks bind verbatim.** `` `ledger balances` `` is a literal command
   name, never a reference to be resolved.
5. **Ambiguity is an open question.** Two possible resolutions of a name, or
   two introductions of it, stop generate with a question, never a guess
   (deduce-or-fail, spec Section 5).
6. **Renames are ordinary edits.** A rename replaces decisions under set
   semantics; provenance keeps the chain reviewable.

## What This Sketch Commits, and What Stays Open

Committed by this document, on top of the walk-through's eight rules:
comment grouping as human-only, the language tag in canonical readings,
composition as plain merge of meta bases, the meta-decision block kinds
(concepts, demands with verbatim questions, defaults, pattern maps, coping,
test obligations, exported guarantees with rigor tags), and the six
cross-reference rules.

Open for the prototype phase:

- The pattern-matching formalism behind "obligation patterns" (how
  `"every <row> becomes exactly one <entity>"` is specified and matched
  deterministically; Survey A points to Statix-style constraints or K-style
  rewriting).
- The strength lattice beyond default-vs-Solution (does a language ever
  outrank another?).
- The precise linting definition of "a mechanism without test obligations
  does not lint."
- How `records`' policy decisions realize (auth is the deepest mechanism
  territory the sketch touches without expanding).
