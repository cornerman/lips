# Multi-World Builds: One Program, Several Backends

Status: design, agreed in discussion 2026-08-07. No code. Companion of
`2026-08-07-world-files-design.md` (a world is data, not a constructor), which
is a prerequisite. Supersedes the ledger line "Nothing translates between
worlds: a user-service backup is a different intent, minted into a different
engine" in `README.md`.

## The Defect

You must name the world at the earliest possible moment, in the step you want
to run least often. `lips generate --target nixos` burns the choice into the
generation id, and a home-manager variant of the same intent is a different
language, minted separately, drifting silently. Two observations force the
change.

**You do not know the world when you write.** Writing "serve the site on port
8080" says nothing about systemd, launchd or a Deployment. Requiring the answer
before the first mint is asking for a decision the program does not contain.

**Most of a program is world-free anyway.** A program carries two kinds of
content, and only one of them is world-specific:

- the *thing itself* (a server, its source, its binary, its image), which is a
  derivation and means the same in every world;
- the *placement* (a system unit, a user service, a Deployment, a Terraform
  resource), which is the world.

So a world is not a platform. **A world is the placement vocabulary: what turns
a built thing into a running thing.** `Nix/Flake.hs` already emits the
world-free half (`artifact.*`, `site`, `site-claims`, `claims`) identically for
all four worlds.

## Decisions

### 1. The Grammar Is the Cross-World Contract

The engine splits along the line that already exists in it:

    api.web.lips                     <- yours
    web/
      web.grammar                    <- shared: patterns. The middle layer.
      web.generation                 <- mint events, one per backend
      nixos/    web.rules  web.expect  nixos.world
      kubenix/  web.rules  web.expect  kubenix.world
      out/
        api/nixos/    api/kubenix/   <- one compiled dir per backend

Patterns are shared; rules, demands and `.expect` are per world. A second
backend is accepted only if it reads exactly the same patterns with the same
captures.

The decisive argument is error quality, not tidiness. With patterns shared, a
kubenix-only line compiled to nixos fails with "read, but lands nowhere in
world nixos": a true statement that names the world and tells you the program
is not portable. With patterns per world, the same line fails as "unreadable",
which sends you to `generate`, where regenerating cannot help. The shared
pattern set buys the correct signpost.

`.expect` cannot be shared: "a systemd timer exists" has no world-neutral
spelling.

### 2. The Grammar Is Append-Only Across Backends

A mint for a second backend may add patterns (kubenix may need a namespace that
nixos never needed), never modify or delete existing ones. The guard is
structural and cheap: the old lines must come back byte-identical, and each
line is stamped with the mint event that wrote it.

Changing an existing pattern is a full re-mint of the language under
`--compat`, re-realizing every world and holding every world's `.expect`. Loud,
human-decided, exactly as regeneration is gated today.

Consequence, named rather than hidden: when the grammar grows for world B, a
program *using* the new line stops being portable to world A. That is reported
at compile, per world, never at mint and never silently.

### 3. `--target a,b` Mints Several Backends at Once

`generate` already takes several programs in one call and generalizes one
grammar across them. The same move on the world axis: `--target nixos,kubenix`
mints both backends, with both worlds' needs visible to the model while the
grammar is being written. Generalizing beats appending, so this is also the
recommended way to add a backend later: re-mint the worlds together. Costs a
model call per existing world, which is the price of a grammar that was
designed for all of them rather than patched for the newest.

### 4. Compile Builds Every Backend

`lips compile api.web.lips` builds all backends into
`<language>/out/<instance>/<world>/` and prints each world's rungs. `--target`
narrows. Nothing is guessed: "multi-world build" means what it says.

Cost, accepted: one nix contract evaluation per world.
`lib.modulesFromDir` then exposes the same program under every world attribute
it was minted for (`nixosModules.api` and `kubenixModules.api`), which is what
lets one repo hold a dev VM and a cluster deployment of one program.

### 5. `artifact.world`: The World-Free World

A world file that fills no slots is legal. Compile then emits a flake with only
lips' own world-neutral outputs (`artifact.*`, `site`, `claims`) and no module.
This is `DESIGN.md`'s future PACKAGE axis, obtained with no kernel case at all:
the empty world file.

It is the producer side of cross-world composition. A program that builds a
server and its OCI image (`dockerTools`) has no placement of its own; a sibling
kubenix program names the image. `DESIGN.md`'s objection ("an artifact always
needs a consumer, so build to nowhere is a non-thing") is answered rather than
ignored: under composition the consumer is a sibling program.

## The Middle Layer, Named

The split above is a platform-independent model plus a lowering, under
different names: `web.grammar` is world-neutral, `<world>/web.rules` lowers it
into one world's vocabulary. That is the shape classic model-driven development
died of, so the two properties that keep it alive here must be stated:

- **It is not universal.** The grammar is minted from your words for your
  problem. Nobody has to learn or maintain a general notation.
- **It is not hand-edited.** So it cannot rot into a second source of truth.

A *general* middle layer, a world-neutral vocabulary of "periodic task",
"persistent path", "listening port" that every world lowers, is the hard
version, and it is forbidden where you would want it: that vocabulary is domain
knowledge, which can never live in the kernel. It would have to be data, which
makes it another engine whose rules emit facts rather than option paths.
Deliberately deferred.

## Worked Example: The Football Manager

The question that started this: a large application, packaged as an image,
deployed to Kubernetes, with infrastructure in Terraform. Under these decisions
it is four programs, each in its own language, meeting at derivations:

    manager.app.lips     --target artifact          builds the server and its OCI image
    manager.deploy.lips  --target kubenix           Deployment naming that image
    cluster.infra.lips   --target terranix          the cluster it lands on
    manager.dev.lips     --target nixos             optional: the same app as a local VM service

The app program never learns what a Deployment is; the deploy program never
learns Go. Only the third piece is still missing physics: the reference by
which one program names another's output.

## Crossing a World Boundary: What the Seam Carries

Exactly two things can cross between worlds:

- **a store path** -- valid only when the consumer evaluates in the same Nix (a
  nixos unit naming `${artifact.app}`: yes; a cluster pulling
  `image: /nix/store/...`: a silent lie);
- **a string in a foreign namespace** -- an image ref, an AMI id, a DNS name.

A per-world "in-place vs shipped" kernel refusal for store paths was proposed
and RETRACTED: whether a store path is meaningful depends on where the
consuming tool runs (local tofu uploading a Lambda zip is legitimate; a local
k3s node can mount the store), which lips cannot know. The steer belongs in
the world's mint preamble (data), the channel that already says "no machine to
boot in this world"; never a kernel rule.

### The GitOps Assumption

A first draft claimed the foreign-namespace string "is created by an act
(push, apply) lips never performs", so lips could guarantee agreement between
producer and consumer but never existence. Under GitOps that is wrong, and the
correction strengthens the seam:

- **Git is the source of truth.** A reconciler (Flux, ArgoCD, a terraform
  pipeline) performs push/apply from what is merged. lips renders, a human
  merges, the run happens. Nobody owns the run. "Running is not a lips verb"
  survives, stronger: running is nobody's verb.
- **The exported string is therefore derivable at compile, not just stated.**
  Strongest form is content-addressed: the image tag is a function of the
  derivation itself (the Nix output hash, known at eval without building; the
  OCI digest would need the build). The manifest then names exactly the bytes
  the pipeline pushes -- the export is true by construction, not by
  convention. The registry prefix stays an ordinary stated fact. The kernel
  stays blind: a derivation hash is Nix-level knowledge, like `${pkgs...}`,
  not domain knowledge.
- **Ordering is the reconciler's semantics.** Manifest before image means
  ImagePullBackOff and retry until true; eventual consistency is GitOps
  physics, not lips'.
- **The chain closes.** The build-and-push pipeline is itself a declarative
  file in a repo, i.e. a placement vocabulary -- CI as a world -- so even the
  publishing machinery is a candidate lips program: rendered, reviewed,
  reconciled.
- **What lips still never does:** perform the act. compile stays offline and
  deterministic; the one human act is the merge, which is already lips'
  review gate.

### Store Path or Published Reference: Decided Per Field, Not Per World

Both forms coexist inside one world, even inside one program. The deciding
property is who dereferences the value, and where. tofu reading
`aws_lambda_function.<n>.filename` dereferences it itself, on the machine it
runs on, so a store path is correct when tofu runs beside the store; `ami` in
the same rendered output is dereferenced by AWS later, so it must be a
published identifier. kubenix's `image` is dereferenced by a remote kubelet
(published ref), unless the cluster is a local k3s mounting the store.

So the choice is field-level vocabulary knowledge, and the division of labor
is: the KERNEL offers closed value forms only (artifact reference, derived
hash, stated fact) plus deduce-or-fail when a needed fact (registry, bucket)
is unstated, and never knows which form a field wants; the ENGINE's per-world
rules pick the form per emitted option, which is what a rule is (the lowering
of one intent into one field's semantics); the PREAMBLE and `.direction`
(data) steer the mint and carry taste for the ambiguous middle. This is why
the world-level store-path refusal had to be retracted: no world-level fact
decides it.

## What This Does Not Decide

- **Cross-program composition.** `export.*` and `${program.<instance>.<path>}`
  are reserved names, unbuilt. See the `TODO.md` backlog item. Without it the
  worked example above is four programs that cannot name each other. The
  GitOps section above fixes what the reference must be able to carry: a
  stated string, or a value derived from an artifact's own hash.
- **The `.generation` record shape** with several mint events per language:
  append-only event list in one file per language, versus one record per
  backend. Invariant 6 (every `@gen:` id must re-hash from the committed
  record) holds either way and decides nothing between them.
- **Demand duplication.** Demands are per world, so a world-neutral demand
  ("which directory should be backed up?") is written once per backend. Left as
  duplication until it hurts.
- **Migration** of the existing single-world examples and their `.generation`
  records.
