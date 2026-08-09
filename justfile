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

# Full verification: conformance suite + VM boot of the realized module.
# This is the CI gate (nothing calls it automatically yet -- run it by hand
# before a merge); named `ci`, not `check*`, since it is not the same check
# as `lips check` (that one program-vs-contract verb is the `check` recipe
# and `check-expect` below, both host-side and KVM-free).
ci:
    nix flake check -L

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
    export LIPS_MINT_SCHEMA="$PWD/kernel/test/fixtures/options-mini.json"
    export LIPS_MINT_WORLD=nixos
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
