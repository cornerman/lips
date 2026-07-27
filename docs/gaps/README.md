# Gap Reports: CLI-Tool Programs

Three programs that a mint cannot turn into an engine today, kept here with the
evidence rather than in `examples/`, because every consumer of `examples/`
(`just check-expect`, the `lipsModules-eval` flake check) iterates each
`*.lips` and fails loud on a program with no `<language>/` folder.

They stay committed because each one is a repro. Move a program back into
`examples/` the day its blocking gap closes.

| Program | Target | Blocked by |
|---|---|---|
| `logscan.lips` | nixos | behavior-as-source, templated source |
| `board.lips` | home-manager | ~~capture-keyed artifact names~~ (closed; retry the mint) |
| `habit.lips` | home-manager | ~~capture-keyed artifact names~~ (closed), language branching |

Finding 2 is closed in the kernel, so `board` and `habit` are worth re-minting;
what blocked them mechanically is gone. `logscan` remains blocked on findings 1
and 4, which are design work.

## What Was Run

Six mints on 2026-07-27, three programs against `ollama/qwen3-coder:30b` and
the same three against `claude-sonnet-5`. No engine survived the gate, so
nothing was written: a refused mint costs the author nothing, which is why
running all six was cheap.

## Finding 1: Behavior as Source (the important one)

`claude-sonnet-5`, minting `logscan.lips`, filed this itself:

> these lines fully determine the filtering algorithm that must be hand-written
> into the artifact's Go source. there is no NixOS option or value grammar that
> can hold "an algorithm"; the current engine can only capture them as
> decorative concepts and rely on a fixed, hand-authored source file, so a
> future edit that changes the filtering rule (e.g. "any field" instead of
> "every field") is silently ignored by re-realization

The blocked lines were `keep a line only when every field named on the command
line equals the value given with it.` and `print each kept line unchanged.`

This is not a missing convenience. A program line that states behavior gets
absorbed as a `Concept`, and a `Concept` does not realize, so editing that line
changes nothing in the output. The author reads a program whose lines look
load-bearing and are not.

Deduce-or-fail covers the line lips cannot READ. It does not cover the line
lips reads, silently declines to honor, and drops. That is the gap: the mint
may quietly demote any inconvenient line to decoration, and no structural guard
notices. Compare invariant 2 (fail loud, never guess) and the `VTail` decision
recorded in the ledger, where emitting a literal instead of failing was
rejected for exactly this reason.

Two candidate remedies, neither designed yet:

- Make silent demotion impossible: require the mint to justify every `Concept`
  it creates from a line the author wrote as an assertion, and refuse a
  `Concept` that carries a verb the engine never maps.
- Make the dependency visible: record which program lines the compiled source
  depends on, so a later edit to one of them fails loud demanding a re-mint,
  instead of compiling to an unchanged binary.

Findings 3 and 4 below are the same disease in smaller form.

## Finding 2: Capture-Keyed Artifact Names (CLOSED)

Closed in the kernel: a capture now keys an artifact and fills a value. See the
ledger entry "Captures are first-class". The original report follows, since it
is what drove the fix.

`claude-sonnet-5` hit this on both `board.lips` and `habit.lips`, phrasing it
the same way each time:

    rule r3: ${artifact.<name>} is not a valid build reference; the name after
    artifact. must be a plain identifier: ${artifact.<cmd>}

    as written: match fact tool.<cmd> => artifact.<cmd>.builder "buildGoModule"
      ; artifact.<cmd>.args.pname "<value>" ; artifact.<cmd>.args.src
      "./artifacts/<cmd>" ; home.packages "[ ${artifact.<cmd>} ]"

Value-keyed *options* landed (the ledger's "Value-keyed options" milestone: a
`<name>` capture binds a segment and fills every occurrence in the emit path).
Value-keyed *artifacts* did not. So the mint can key an nginx vhost by a
program value but cannot key a build by one, and the natural engine for "install
a command called X" is unwritable.

This looks like the most contained of the findings: artifact names are subject
paths, and capture fill already exists for those. The reference form
`${artifact.<name>}` is the part that rejects a hole.

## Finding 3: Language Branching

`claude-sonnet-5`, minting `habit.lips`, declined to fake a builder choice:

> the artifact builder (buildGoModule) is hardcoded to match the observed "go"
> text; lips has no mechanism to branch a builder choice on an arbitrary
> captured language token, so if a future edit changes "go" to another language
> the same rule would wrongly still emit buildGoModule. The line is therefore
> treated as a decorative concept rather than a fact driving the builder.

The refusal is correct behavior, and the reasoning is the tell: the fallback was
again "treat the line as decoration". Note the program line it could not honor
is one the http example *does* carry (`write the server in go, using only the
standard library`), where it maps to a `steer` decision and the builder is a
literal. So the existing example works only because nobody edits that word.

Branching on a captured value is computation, which the closed value grammar
forbids by construction. So this is either permanently out of scope (and the
honest fix is that changing the language word must fail loud, not silently
keep `buildGoModule`) or it wants the glue channel.

## Finding 4: Templated Source, Two New Repros

Already in `TODO.md` as a backlog item, with the `server.lips` route repro.
Two independent mints reproduced it on different lines:

- `install the tool as the command <name>.` The command name is a program value
  that has to become the built binary's name, i.e. it must land inside the
  artifact's `pname` and its Go module. Source heredocs have no holes, so a
  rename in the program cannot reach the compiled binary.
- `qwen3-coder:30b` reported the original per-route shape verbatim
  (`- /hi => status 200`), a line absent from `logscan.lips`, so treat that one
  as contaminated output rather than a finding.

## Finding 5: A CLI Engine Has Nothing to Pin

`claude-sonnet-5` minting `habit.lips` was rejected by a structural guard:

    examples/habit.lips checks options that hold a package or build, not a
    plain value:  home.packages (check a5)

`uncheckableExpects` is right to refuse it: `home.packages` holds a derivation
the stubbed check eval cannot force. But follow it through. A pure CLI tool
emits *only* derivation-valued options, so no assertion it could write is
checkable, so its contract is necessarily empty, and `uncheckableExpects`
returns `[]` for an empty list, which passes.

An empty contract passes vacuously. Invariant 5, the committed `.expect` gating
regeneration, therefore has no force for this whole class of program. Either
the class needs a different kind of assertion (something that survives being a
derivation, e.g. asserting the built binary's *name* or that a wrapper's text
contains the program value), or the guard should refuse an engine whose
contract is empty, which would currently refuse `greet` too.

## Finding 6: Unbound Target Holes (Model Error, Format Smell)

`qwen3-coder:30b` failed this way on nearly every pattern it wrote:

    pattern p1: target holes not bound by template: value,value,value
      as written: pattern show a kanban board in the terminal.
        => fact board.show "<value>" ; fact board.source "<value>"

The template has no hole, so `<value>` binds to nothing. `claude-sonnet-5` never
made this mistake, so it reads as a capability difference, not a kernel gap.

Worth noting anyway: the pattern side names its holes after the *template's*
holes, while the rule side uses the fixed name `<value>`. Two hole namespaces,
one syntax. A weaker model reliably confuses them, which by invariant 4 makes it
a format question rather than a prompt question.

## Cross-Cutting Note

Findings 1, 3 and 4 all end at the same place: a program value or program
sentence that must reach *inside* the compiled program. lips today moves such
values through the *module* instead, which is why `hello.http` works: the port
and response text ride `systemd.services.<self>.environment` and `main.go` reads
them with `os.Getenv`. That trick needs a service to carry the environment. A
bare command has none, so it needs a wrapper artifact, and the wrapper needs
Finding 2 to be keyed by the command's name.

So the CLI-tool class is blocked on Finding 2 mechanically, and on Finding 1
honestly.
