# The Mint Round Loop

**Status:** decided, not built. Supersedes the backlog entry "Mint round loop --
deferred", whose cost argument the growth mint measured obsolete.

## Why It Is Back

The backlog deferred re-prompting a refused mint on three grounds: every round
re-emits the whole engine (expensive output tokens), every round triggers a fresh
nix gate run, and a prompt whose tail changes each request defeats prompt
caching. Two of the three are now measured gone (DESIGN §13):

- Output: a patch reply is 3,765 tokens where a whole engine was 26,598.
- Input: 8 fresh tokens against 99,357 read from cache, so the fixed prefix is
  already the cheap part.
- Gate: still real. A claim that boots costs 27-46s, and that is the price a
  round pays.

And there is now a case that names the hole exactly. Minting `examples/website`
under the boot rule refused on a failing machine claim (`claim serving: exit was
7`, darkhttpd rejecting its own `--addr`), for $3.23 and 17 minutes, and the
finding reached the next call only because a human typed it into a direction
file. That is the loop being closed by hand.

## The Shape

A round is a PATCH MINT whose basis is the REFUSED engine.

Round 1 is exactly today's call. If a gate refuses and rounds remain, round 2
receives, in this order:

1. the same system prompt (world preambles, body, direction) -- unchanged, so the
   cached prefix survives,
2. the same corpus,
3. the refused engine, rendered by `replyLinesOf` as the basis, with the patch
   rules from `assets/mint/patch.md`,
4. the findings, as the newest tail.

It answers a patch, which `mergeReply` folds into the refused engine, and the
SAME gate judges it. No new gate call site: `lips dry-run` as a model-callable
rehearsal stays permanently rejected, because a second call site can drift from
the one that commits.

## Decisions

**1. One retry by default; `--max-rounds N` changes it.** A refused opus round
cost $3.23 measured, so the default spends at most one extra call. `N` counts
model calls, not retries (`--max-rounds 1` disables the loop and is the old
behaviour exactly).

**2. `--max-rounds` does NOT enter `.generation`, and this is not an oversight.**
Invariant 6 pins what steers the RESULT. The winning round's prompt already
contains the findings section, so the record fully determines the engine that was
accepted, and the flag only decided whether a second call was allowed to happen.
What does enter the record is the basis: `retry <genid>` naming the record of the
round it grew out of, so a chain of attempts is traceable exactly as a chain of
growth mints is.

**3. What goes back: the refusal text lips already prints, verbatim, plus the
failing observation's captured output, truncated.** The verdict says WHICH gate
refused; the log says WHY (`darkhttpd: malformed --addr` is the diagnosis, and it
appears nowhere in the verdict). Truncation reuses the record's existing
convention (`Lips.Generate.PiJson.truncated`: 4000 characters, with the elision
stated), so a VM boot log cannot crowd out the prompt. No new wording is invented:
a third rendering of what lips already says in words is a third thing to keep
true.

**4. Only ENGINE refusals are retryable.** A gate verdict about the engine (an
unreadable line, an unmapped decision, a broken expect, a failing claim, an
artifact that will not build, a missing report, a low-confidence line) is the
model's to fix, so it retries. An environment failure is not: no `/dev/kvm`, nix
missing, a schema that will not build, a world that does not resolve. Those die
on the first attempt as they do today -- retrying them burns money on a fact
about the machine.

**5. A failed round leaves nothing extra.** The final refusal writes its `.gap`
as today; intermediate rounds write nothing to the language folder (a superseded
refusal in an engine folder is clutter that outlives its meaning). The unsealed
timing file gains `rounds: N` and keeps one phase line per round, so the cost of
converging is visible where every other cost already is.

**6. The loop lives inside `generate`, around the call-and-gate sequence.** Not
around an agent that asks: the backlog's "if the loop returns it belongs around
an agent" was written when a round re-emitted everything. With a patch reply the
cheap thing IS the round, and keeping it inside `generate` keeps one door to the
model and one gate.

## What Would Falsify This

If the second round mostly repeats the first (as the blind re-mint did, DESIGN
§13), the loop is paying for nothing and the findings are not the missing
information -- in which case the answer is a better refusal text, not more
rounds. The measurement is cheap and already instrumented: `rounds:` in the
timing file, and the verdict of each round. Run it on the case that motivated
this (`website` under the boot rule, `--fresh`, `--max-rounds 2`) and compare
against the recorded single-round refusal.
