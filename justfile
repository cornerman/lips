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
