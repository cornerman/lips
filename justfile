# lips — command index. The deliverable (calculus + suite) lives in kernel/;
# examples/ holds demonstration programs; the flake ties them together.
# Recipes are thin wrappers over nix so nothing is installed globally.

# Recipes run from the justfile directory (repo root), where the flake lives.
# Using "." (not "path:.") keeps nix on git semantics, so untracked runtime
# dirs like .corral stay out of the flake tree.

# List available recipes.
default:
    @just --list

# Build the lips binary (nix package) and print its path.
build:
    nix build . --print-out-paths

# Run the conformance suite (fast: compiles Spec.hs in the dev shell).
test:
    nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -itest test/Spec.hs \
      -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec'

# Full verification: conformance suite + VM boot of the realized module,
# then the draft-door wordings (test-draft below), which hspec cannot see and
# which rotted unnoticed for four days when nothing ran them -- chained here so
# the one pre-merge command covers them. This is the CI gate (nothing calls it
# automatically yet -- run it by hand before a merge); named `ci`, not
# `check*`, since it is not the same check as `lips check` (that one
# program-vs-contract verb is the `check` recipe and `check-expect` below,
# both host-side and KVM-free).
ci:
    nix flake check -L
    just test-draft

# Behavioral contracts: every example's .expect must hold against its realized
# module (relational option-value gate, ledger 13). Host-side (uses nix eval),
# no KVM. This is the same check generate runs before accepting an engine.
check-expect:
    #!/usr/bin/env bash
    set -euo pipefail
    # Programs are <instance>.<language>.lips (the .lips marker is what every
    # editor and language server associates) and are the only files at this
    # level: everything minted lives in the <language>/ folder beside them.
    for p in examples/*.lips; do
      nix run . -- check "$p"
    done

# Deterministic realize: program + .lang -> a module directory (default.nix +
# artifacts/), no model, offline. Writes <language>/out/<instance>/ by default.
compile program:
    nix run . -- compile "{{program}}"

# The edit loop: recompile on every save, and press g to grow the language (which
# runs generate, the one AI step) or q to stop. Needs a terminal.
watch program:
    nix run . -- compile --watch "{{program}}"

# Running is not a lips verb: `compile` prints the exact `nix run`/`nix build`
# commands over the compiled dir (exec/shell for an artifact, container/vm for a
# system module). Run one of those printed commands to run the program.

# Verify one program's committed behavioral contract against its realized module.
# Mirrors `lips check <program>` one-to-one; the full suite is `just ci`.
check program:
    nix run . -- check "{{program}}"

# The one AI step: mint language+engine via pi, validate, write .lang/.decisions/.generation.
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{model}}" ]; then
      nix run . -- generate --model "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi

# Look an option path or a domain word up in the pinned schema: the same lookup
# the mint gets through its one tool, so you can see exactly what it would read.
# Read-only, no AI.
options query target="nixos":
    nix run . -- options --target "{{target}}" "{{query}}"

# The engine gates as `lips check` runs them: over a committed engine, and (in
# a later task) over a draft read from stdin. Shell-level, because the verdict
# is an exit code plus the wording of a refusal, and check dies rather than
# returning -- hspec cannot see either. Builds the binary in the dev shell, the
# way `test` builds the suite, so this needs no `nix run` and no `git add`.
test-draft:
    #!/usr/bin/env bash
    set -euo pipefail
    nix develop -c bash -c 'cd kernel && ghc -Wall -isrc -iapp app/Main.hs \
      -outputdir /tmp/lips-build-cli -o /tmp/lips-cli'
    lips=/tmp/lips-cli
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    # generate states which worlds a draft is judged in; nothing is guessed.
    export LIPS_MINT_WORLDS=nixos
    export LIPS_MINT_PROGRAMS="$tmp/one.watch.lips"
    # The committed shape: a shared grammar at the language level, one world's
    # rules in its own folder. Hand-written, so no .generation beside them.
    mkdir -p "$tmp/watch/nixos"
    printf 'watch 30 seconds\n' > "$tmp/one.watch.lips"
    cat > "$tmp/watch/watch.grammar" <<'EOF'
    p1 meta lang.pattern.p1 stated "watch <secs> seconds => fact watch.a \"<secs>\""
    p2 meta lang.pattern.p2 stated "watch <n> seconds => fact watch.b \"<n>\""
    EOF
    cat > "$tmp/watch/nixos/watch.rules" <<'EOF'
    r1 meta engine.rule.r1 stated "match fact watch.a => systemd.services.w.environment.A \"<value:int>\""
    r2 meta engine.rule.r2 stated "match fact watch.b => systemd.services.w.environment.B \"<value:int>\""
    EOF
    sed -i 's/^    //' "$tmp/watch/watch.grammar" "$tmp/watch/nixos/watch.rules"
    # A committed engine unsound on its own terms must be refused, not diagnosed.
    if "$lips" check "$tmp/one.watch.lips" > "$tmp/out" 2>&1; then
      echo "FAIL: check accepted an engine whose patterns are not orthogonal"; cat "$tmp/out"; exit 1
    fi
    grep -q "patterns read the same line" "$tmp/out" || { echo "FAIL: refusal did not name the overlap"; cat "$tmp/out"; exit 1; }
    # The same defect in a DRAFT, read from stdin in the mint's reply format.
    cat > "$tmp/draft.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.a "<secs>"
    0.95 p2 pattern watch <n> seconds => fact watch.b "<n>"
    0.95 r1 match fact watch.a => systemd.services.w.environment.A "<value:int>"
    0.95 r2 match fact watch.b => systemd.services.w.environment.B "<value:int>"
    EOF
    sed -i 's/^    //' "$tmp/draft.txt"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/draft.txt" > "$tmp/out2" 2>&1; then
      echo "FAIL: --draft accepted overlapping patterns"; cat "$tmp/out2"; exit 1
    fi
    grep -q "patterns read the same line" "$tmp/out2" || { echo "FAIL: --draft refusal did not name the overlap"; cat "$tmp/out2"; exit 1; }
    # A sound draft is accepted, and says what it did not check.
    cat > "$tmp/good.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    EOF
    sed -i 's/^    //' "$tmp/good.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/good.txt" > "$tmp/out3" 2>&1 \
      || { echo "FAIL: a sound draft was refused"; cat "$tmp/out3"; exit 1; }
    grep -q "NOT run" "$tmp/out3" || { echo "FAIL: the skipped gates were not reported"; cat "$tmp/out3"; exit 1; }
    # An option that does not exist is refused, when generate hands the draft
    # path the schema it grounded the mint against (check itself stays
    # nixpkgs-free, so the gate can only run on the mint side).
    cat > "$tmp/badopt.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => services.ngnix.port "<value:int>"
    EOF
    sed -i 's/^    //' "$tmp/badopt.txt"
    export LIPS_MINT_SCHEMAS="nixos=$PWD/kernel/test/fixtures/options-mini.json"
    export LIPS_MINT_WORLDS=nixos
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/badopt.txt" > "$tmp/out4" 2>&1; then
      echo "FAIL: --draft accepted an option that does not exist"; cat "$tmp/out4"; exit 1
    fi
    grep -q "ngnix" "$tmp/out4" || { echo "FAIL: the refusal did not name the bad option"; cat "$tmp/out4"; exit 1; }
    # The same draft with the option the fixture does declare passes, and the
    # contract it was handed is the one it is graded against.
    cat > "$tmp/goodopt.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => services.x.port "<value:int>"
    0.95 a1 expect services.x.port from watch.interval
    EOF
    sed -i 's/^    //' "$tmp/goodopt.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/goodopt.txt" > "$tmp/out5" 2>&1 \
      || { echo "FAIL: a sound, grounded draft was refused"; cat "$tmp/out5"; exit 1; }
    grep -q "contract: 1 check" "$tmp/out5" || { echo "FAIL: the expect gate did not run on the draft"; cat "$tmp/out5"; exit 1; }
    # A draft for SEVERAL worlds: the patterns are shared, the rules are tagged,
    # and every world is judged. This is what one mint answers with.
    unset LIPS_MINT_SCHEMAS
    export LIPS_MINT_WORLDS=nixos,home-manager
    cat > "$tmp/two.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 @nixos match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.95 r2 @home-manager match fact watch.interval => systemd.user.services.w.Service.Environment "\"S=<value>\""
    EOF
    sed -i 's/^    //' "$tmp/two.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/two.txt" > "$tmp/out6" 2>&1 \
      || { echo "FAIL: a sound two-world draft was refused"; cat "$tmp/out6"; exit 1; }
    grep -q "world nixos" "$tmp/out6" || { echo "FAIL: nixos was not judged"; cat "$tmp/out6"; exit 1; }
    grep -q "world home-manager" "$tmp/out6" || { echo "FAIL: home-manager was not judged"; cat "$tmp/out6"; exit 1; }
    # The signal the whole one-call design exists for: a rule reading a part its
    # pattern does not produce is named INSIDE the mint's own call, so the model
    # can still fix the PATTERN. (The engine gate cannot judge this one: a
    # one-part value's token count comes from the program, not the pattern, so
    # it is refinement that names it -- which the draft path runs.)
    cat > "$tmp/parts.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 @nixos match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.95 r2 @home-manager match fact watch.interval => systemd.user.services.w.Service.Environment "\"S=<value.2>\""
    EOF
    sed -i 's/^    //' "$tmp/parts.txt"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/parts.txt" > "$tmp/out7" 2>&1; then
      echo "FAIL: --draft accepted a rule reading a part that does not exist"; cat "$tmp/out7"; exit 1
    fi
    grep -q "<value.2> out of range" "$tmp/out7" \
      || { echo "FAIL: the refusal did not name the missing part"; cat "$tmp/out7"; exit 1; }
    # A world may declare a fact it cannot place, but only where another world
    # spends it. Declaring it in EVERY world is how a mint could otherwise drop a
    # word of the program silently, so that is the case this checks.
    cat > "$tmp/ign.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 p2 pattern with tag <t> => fact watch.tag "<t>"
    0.95 r1 @nixos match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.95 r2 @home-manager match fact watch.interval => systemd.user.services.w.Service.Environment "\"S=<value>\""
    0.9 i1 @nixos ignore fact watch.tag "a machine has no tags"
    0.9 i2 @home-manager ignore fact watch.tag "a user session has no tags"
    EOF
    sed -i 's/^    //' "$tmp/ign.txt"
    printf 'watch 30 seconds\nwith tag nightly\n' > "$tmp/one.watch.lips"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/ign.txt" > "$tmp/out8" 2>&1; then
      echo "FAIL: --draft accepted a fact every world ignores"; cat "$tmp/out8"; exit 1
    fi
    grep -q "no world of this language places" "$tmp/out8" \
      || { echo "FAIL: the refusal did not name the unplaced fact"; cat "$tmp/out8"; exit 1; }
    # The same draft, with one world placing it, holds.
    cat > "$tmp/ign2.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 p2 pattern with tag <t> => fact watch.tag "<t>"
    0.95 r1 @nixos match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.95 r2 @home-manager match fact watch.interval => systemd.user.services.w.Service.Environment "\"S=<value>\""
    0.9 i1 @nixos ignore fact watch.tag "a machine has no tags"
    0.95 r3 @home-manager match fact watch.tag => systemd.user.services.w.Unit.Description "\"<value>\""
    EOF
    sed -i 's/^    //' "$tmp/ign2.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/ign2.txt" > "$tmp/out9" 2>&1 \
      || { echo "FAIL: an ignore another world places was refused"; cat "$tmp/out9"; exit 1; }
    grep -q "nixos ignores watch.tag" "$tmp/out9" \
      || { echo "FAIL: the run did not say what nixos ignores"; cat "$tmp/out9"; exit 1; }
    # A contract that can never hold: the fact has two parts, the rule assembles
    # the option's text out of them, and the expect reads the fact WHOLE -- so
    # the parts joined by a space appear in the option nowhere. Refused inside
    # the mint's own call, where the model can still write the form that holds.
    export LIPS_MINT_WORLDS=nixos
    printf 'watch 30 seconds\nrun at 03:00\n' > "$tmp/one.watch.lips"
    cat > "$tmp/whole.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 p2 pattern run at <hh>:<mm> => fact watch.at "<hh> <mm>"
    0.95 r1 match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.95 r2 match fact watch.at => systemd.timers.w.timerConfig.OnCalendar "\"*-*-* <value.1>:<value.2>:00\""
    0.95 a1 expect systemd.timers.w.timerConfig.OnCalendar from watch.at
    EOF
    sed -i 's/^    //' "$tmp/whole.txt"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/whole.txt" > "$tmp/out10" 2>&1; then
      echo "FAIL: --draft accepted a check that can never hold"; cat "$tmp/out10"; exit 1
    fi
    grep -q "appear in it nowhere" "$tmp/out10" \
      || { echo "FAIL: the refusal did not name the unholdable check"; cat "$tmp/out10"; exit 1; }
    grep -q 'is "\*-\*-\* <value.1>:<value.2>:00"' "$tmp/out10" \
      || { echo "FAIL: the refusal did not name the form that holds"; cat "$tmp/out10"; exit 1; }
    # The same draft, stating the text its rule assembles, holds -- and the
    # contract really runs against the realized module.
    sed 's|from watch.at$|from watch.at is "*-*-* <value.1>:<value.2>:00"|' "$tmp/whole.txt" > "$tmp/tpl.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/tpl.txt" > "$tmp/out11" 2>&1 \
      || { echo "FAIL: a contract stating the assembled text was refused"; cat "$tmp/out11"; exit 1; }
    grep -q "contract: 1 check" "$tmp/out11" \
      || { echo "FAIL: the expect gate did not run on the template draft"; cat "$tmp/out11"; exit 1; }
    # Staging is the TOOL's alone. The verb only reports, so a human (and this
    # recipe) can run it over any draft without an answer appearing behind their
    # back; only submit_draft writes the file generate then reads as the answer.
    export LIPS_MINT_ANSWER="$tmp/answer"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/tpl.txt" > "$tmp/out12" 2>&1 \
      || { echo "FAIL: a sound draft was refused with an answer path set"; cat "$tmp/out12"; exit 1; }
    if [ -e "$tmp/answer" ]; then
      echo "FAIL: the check verb staged an answer; only submit_draft may"; exit 1
    fi
    unset LIPS_MINT_ANSWER
    # A PATCH is judged as the engine it BECOMES: generate names the language
    # folder it grows from (LIPS_MINT_BASIS), the committed pattern is merged in,
    # and a reply carrying ONLY a rule is therefore a complete engine. Without
    # the merge this draft reads as a language that cannot read its own program.
    export LIPS_MINT_WORLDS=nixos
    grown=$(mktemp -d -p "$tmp")
    export LIPS_MINT_BASIS="$grown/watch"
    export LIPS_MINT_PROGRAMS="$grown/one.watch.lips"
    mkdir -p "$grown/watch/nixos"
    printf 'watch 30 seconds\n' > "$grown/one.watch.lips"
    printf 'p1 meta lang.pattern.p1 stated "watch <secs> seconds => fact watch.interval \\"<secs>\\"" @gen:aaa\n' \
      > "$grown/watch/watch.grammar"
    printf 'r1 meta engine.rule.r1 stated "match fact watch.interval => systemd.services.w.environment.S \\"<value:int>\\"" @gen:aaa\n' \
      > "$grown/watch/nixos/watch.rules"
    printf '0.95 r1 match fact watch.interval => systemd.services.w.environment.T "<value:int>"\n' > "$grown/patch.txt"
    "$lips" check --draft "$grown/one.watch.lips" < "$grown/patch.txt" > "$tmp/out13" 2>&1 \
      || { echo "FAIL: a patch against a committed engine was refused"; cat "$tmp/out13"; exit 1; }
    grep -q "1 of 1 lines crystallize" "$tmp/out13" \
      || { echo "FAIL: the inherited pattern did not reach the draft"; cat "$tmp/out13"; exit 1; }
    # Without the basis the same patch is not an engine at all, which is what says
    # the merge is doing the work rather than something else.
    unset LIPS_MINT_BASIS
    if "$lips" check --draft "$grown/one.watch.lips" < "$grown/patch.txt" > "$tmp/out14" 2>&1; then
      echo "FAIL: a bare patch was accepted as a whole engine"; cat "$tmp/out14"; exit 1
    fi
    # A RESUBMISSION is a patch of the draft this call already submitted, so a
    # retry restates only what it changes instead of re-emitting the engine
    # (output tokens are the mint's wall clock, DESIGN 13). The running file is
    # where the call's submissions accumulate; --running names it.
    export LIPS_MINT_BASIS="$grown/watch"
    running="$tmp/running"
    rm -f "$running"
    "$lips" check --draft --running "$running" "$grown/one.watch.lips" < "$grown/patch.txt" > "$tmp/out15" 2>&1 \
      || { echo "FAIL: the first submission of a call was refused"; cat "$tmp/out15"; exit 1; }
    # The second submission names only the contract, and holds only because the
    # first one's rule (environment.T, replacing the committed environment.S) is
    # still in force.
    printf '0.95 a1 expect systemd.services.w.environment.T from watch.interval\n' > "$grown/patch2.txt"
    "$lips" check --draft --running "$running" "$grown/one.watch.lips" < "$grown/patch2.txt" > "$tmp/out16" 2>&1 \
      || { echo "FAIL: a patch of the call's own draft was refused"; cat "$tmp/out16"; exit 1; }
    grep -q "contract: 1 check" "$tmp/out16" \
      || { echo "FAIL: the accumulated rule did not reach the contract"; cat "$tmp/out16"; exit 1; }
    # The same second patch against an EMPTY running file cannot hold: the
    # committed engine sets environment.S, so the option the contract names is
    # set by nothing. This is what says the accumulation is doing the work.
    rm -f "$running"
    if "$lips" check --draft --running "$running" "$grown/one.watch.lips" < "$grown/patch2.txt" > "$tmp/out17" 2>&1; then
      echo "FAIL: a contract on an option no rule sets was accepted"; cat "$tmp/out17"; exit 1
    fi
    # A REFUSED submission accumulates too, which is the case the cost is in: the
    # model fixes the line the gate named and keeps everything else it wrote.
    cat > "$grown/bad.txt" <<'EOF'
    0.95 r1 match fact watch.interval => systemd.services.w.environment.T "<value.9>"
    0.95 a1 expect systemd.services.w.environment.T from watch.interval
    EOF
    sed -i 's/^    //' "$grown/bad.txt"
    if "$lips" check --draft --running "$running" "$grown/one.watch.lips" < "$grown/bad.txt" > "$tmp/out18" 2>&1; then
      echo "FAIL: a rule reading a part that does not exist was accepted"; cat "$tmp/out18"; exit 1
    fi
    # Only the offending line is restated; the contract line survives the refusal.
    "$lips" check --draft --running "$running" "$grown/one.watch.lips" < "$grown/patch.txt" > "$tmp/out19" 2>&1 \
      || { echo "FAIL: a fix of a refused submission was refused"; cat "$tmp/out19"; exit 1; }
    grep -q "contract: 1 check" "$tmp/out19" \
      || { echo "FAIL: a refused submission's other lines were dropped"; cat "$tmp/out19"; exit 1; }
    # --restart is the escape a patch cannot otherwise give: a line added in an
    # earlier submission cannot be deleted by id, so the model says the running
    # draft is void and this submission stands alone (against the committed
    # engine, which --restart never touches). The contract from before is gone,
    # so the same patch that just held now fails.
    if "$lips" check --draft --running "$running" --restart "$grown/one.watch.lips" < "$grown/patch2.txt" > "$tmp/out20" 2>&1; then
      echo "FAIL: --restart kept the earlier submissions"; cat "$tmp/out20"; exit 1
    fi
    unset LIPS_MINT_BASIS
    # A world's own gate runs in the door: nono's validator refuses a command
    # entry with no sandbox object, which its weak schema cannot see. The world
    # file is the one examples/ ships, beside the program as generate finds it,
    # and the gate builds against the pin generate hands the door per world
    # (LIPS_MINT_PINS), here the flake's own locked nixpkgs.
    export LIPS_MINT_PINS="nono=github:NixOS/nixpkgs/$(nix eval --raw --impure --expr \
      '(builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked.rev')"
    export LIPS_MINT_WORLDS=nono
    sandbox=$(mktemp -d -p "$tmp")
    export LIPS_MINT_PROGRAMS="$sandbox/one.sb.lips"
    cp examples/nono.world "$sandbox/"
    printf 'it may run git.\n' > "$sandbox/one.sb.lips"
    cat > "$sandbox/bare.txt" <<'EOF'
    0.95 p1 pattern it may run <c> => fact cmd.<c>.policy "allow"
    0.95 r1 match fact cmd.<c>.policy => command_policies.commands.<c>.from.session.invocation_policy.default "\"<value>\"" ; meta.name "\"<self>\""
    EOF
    sed -i 's/^    //' "$sandbox/bare.txt"
    if "$lips" check --draft "$sandbox/one.sb.lips" < "$sandbox/bare.txt" > "$tmp/out21" 2>&1; then
      echo "FAIL: --draft accepted a render the world's own gate refuses"; cat "$tmp/out21"; exit 1
    fi
    grep -q "the nono world refuses what lips rendered" "$tmp/out21" \
      || { echo "FAIL: the refusal did not name the world's gate"; cat "$tmp/out21"; exit 1; }
    grep -q "CommandFromConfig" "$tmp/out21" \
      || { echo "FAIL: the refusal did not carry the validator's own words"; cat "$tmp/out21"; exit 1; }
    # The same rule with the sandbox object the validator requires holds.
    sed 's|; meta.name|; command_policies.commands.<c>.from.session.sandbox.fs_read "[ ]" ; meta.name|' \
      "$sandbox/bare.txt" > "$sandbox/boxed.txt"
    "$lips" check --draft "$sandbox/one.sb.lips" < "$sandbox/boxed.txt" > "$tmp/out22" 2>&1 \
      || { echo "FAIL: a render the validator accepts was refused"; cat "$tmp/out22"; exit 1; }
    grep -q "the nono world's own gate" "$tmp/out22" \
      || { echo "FAIL: the world's gate did not run on a sound draft"; cat "$tmp/out22"; exit 1; }
    # The gate builds against the pin the mint records, not lips's baked one:
    # the same sound draft fails on a pin nix cannot fetch, naming it.
    if LIPS_MINT_PINS="nono=path:$tmp/no-such-nixpkgs" \
         "$lips" check --draft "$sandbox/one.sb.lips" < "$sandbox/boxed.txt" > "$tmp/out29" 2>&1; then
      echo "FAIL: the world's gate ignored the pin it was handed"; cat "$tmp/out29"; exit 1
    fi
    grep -q "no-such-nixpkgs" "$tmp/out29" \
      || { echo "FAIL: the world's gate did not fail on the pin"; cat "$tmp/out29"; exit 1; }
    unset LIPS_MINT_PINS
    # No per-program source written by a model: a draft carrying a source block
    # is refused inside the mint's own call, naming the file, whatever else holds.
    export LIPS_MINT_WORLDS=nixos
    export LIPS_MINT_PROGRAMS="$tmp/one.watch.lips"
    printf 'watch 30 seconds\n' > "$tmp/one.watch.lips"
    cat > "$tmp/src.txt" <<'EOF'
    0.95 p1 pattern watch <secs> seconds => fact watch.interval "<secs>"
    0.95 r1 match fact watch.interval => systemd.services.w.environment.S "<value:int>"
    0.9 s1 source watch main.go <<<lips
    package main
    lips>>>
    EOF
    sed -i 's/^    //' "$tmp/src.txt"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/src.txt" > "$tmp/out23" 2>&1; then
      echo "FAIL: --draft accepted model-written source"; cat "$tmp/out23"; exit 1
    fi
    grep -q "watch/main.go" "$tmp/out23" \
      || { echo "FAIL: the no-blob refusal did not name the file"; cat "$tmp/out23"; exit 1; }
    # The same rule for a committed folder: a tree found there is refused by check.
    mkdir -p "$tmp/watch/artifacts/watch"
    printf 'package main\n' > "$tmp/watch/artifacts/watch/main.go"
    if "$lips" check "$tmp/one.watch.lips" > "$tmp/out24" 2>&1; then
      echo "FAIL: check accepted a language folder holding a source tree"; cat "$tmp/out24"; exit 1
    fi
    grep -q "holds a source tree" "$tmp/out24" \
      || { echo "FAIL: check did not name the source tree"; cat "$tmp/out24"; exit 1; }
    rm -rf "$tmp/watch/artifacts"
    # Text the mint writes into a builder's argument is MINT glue, which a claim
    # must run: refused in the door while the model can still add one.
    printf 'say hello\n' > "$tmp/one.watch.lips"
    cat > "$tmp/glue.txt" <<'EOF'
    0.95 p1 pattern say <msg> => fact cmd.msg "<msg>"
    0.95 r1 match fact cmd.msg => artifact.hi.builder "\"writeShellApplication\"" ; artifact.hi.args.name "\"hi\"" ; artifact.hi.args.text "\"echo <value>\"" ; environment.systemPackages "[ ${artifact.hi} ]"
    EOF
    sed -i 's/^    //' "$tmp/glue.txt"
    if "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/glue.txt" > "$tmp/out25" 2>&1; then
      echo "FAIL: --draft accepted mint glue no claim runs"; cat "$tmp/out25"; exit 1
    fi
    grep -q "artifact.hi.args.text" "$tmp/out25" \
      || { echo "FAIL: the glue refusal did not name the argument"; cat "$tmp/out25"; exit 1; }
    # A claim whose run names the artifact pins every word written into it.
    sed 's|\]"$|]" ; claim.c1.run "\\"${artifact.hi}/bin/hi\\"" ; claim.c1.stdout "\\"<value>\\""|' "$tmp/glue.txt" > "$tmp/pinned.txt"
    "$lips" check --draft "$tmp/one.watch.lips" < "$tmp/pinned.txt" > "$tmp/out26" 2>&1 \
      || { echo "FAIL: glue a claim runs was refused"; cat "$tmp/out26"; exit 1; }
    grep -q "glue (mint): artifact.hi.args.text" "$tmp/out26" \
      || { echo "FAIL: the pinned glue was not reported as mint glue"; cat "$tmp/out26"; exit 1; }
    # A mint's clause claims observe the nixpkgs the mint grounds against, which
    # generate hands the door per world (LIPS_MINT_PINS), so they build against
    # the pin `check` reads back from the record. The committed `function`
    # engine, judged as a draft through its basis, states one clause claim: it
    # holds with no pin handed over, and a pin nix cannot fetch must fail it.
    export LIPS_MINT_WORLDS=nixos
    export LIPS_MINT_PROGRAMS="$PWD/examples/function.lips"
    export LIPS_MINT_BASIS="$PWD/examples/function"
    "$lips" check --draft examples/function.lips < /dev/null > "$tmp/out27" 2>&1 \
      || { echo "FAIL: the function engine's clause claim failed as a draft"; cat "$tmp/out27"; exit 1; }
    if LIPS_MINT_PINS="nixos=path:$tmp/no-such-nixpkgs" \
         "$lips" check --draft examples/function.lips < /dev/null > "$tmp/out28" 2>&1; then
      echo "FAIL: the mint's clause claims ignored the pin they were handed"; cat "$tmp/out28"; exit 1
    fi
    grep -q "no-such-nixpkgs" "$tmp/out28" \
      || { echo "FAIL: the clause claims did not fail on the pin"; cat "$tmp/out28"; exit 1; }
    unset LIPS_MINT_BASIS
    echo OK

# Rebuild only the VM smoke check with streamed logs (needs KVM).
vm-smoke:
    nix build .#checks.x86_64-linux.vm-smoke -L

# Drop into the dev shell (ghc with hspec/QuickCheck + just on PATH).
shell:
    nix develop

# Remove local build artifacts (nix outputs live in /tmp and the store).
clean:
    rm -rf /tmp/lips-build /tmp/lips-spec result
