# Expose lips programs in a directory as flake module outputs, grouped by the
# world each engine was minted into. The world is read from the committed
# <language>/<language>.generation record, and the OUTPUT NAME from that world
# file's own `module-attr:` header -- so a house world lands under its own
# attribute with no edit here, exactly as nixos lands under nixosModules. The realized module is
# DERIVED by running `lips compile` in a derivation (offline, deterministic);
# the program and its .lang are the only committed inputs. Each output value is
# the compiled DIRECTORY (default.nix + a staged artifacts/ tree); `imports`
# accepts the directory and resolves its default.nix.
{ pkgs, lib, lips, dir }:
let
  entries = lib.filterAttrs (n: _: lib.hasSuffix ".lips" n) (builtins.readDir dir);

  # <instance>.<language>.lips -> { instance, language }; the singleton
  # shorthand <language>.lips defaults the instance to the language.
  #
  # This restates Lips.Identity's rule in Nix, and knowingly duplicates it: the
  # output ATTRIBUTE NAMES must be known at eval time, so asking the binary
  # (which owns the rule) would mean import-from-derivation. The
  # lipsModules-eval flake check evaluates this over examples/, which holds both
  # shapes, so a drift between the two copies fails the build rather than
  # silently mis-naming a language (it did: taking element 1 of the split read
  # the singleton board.lips as language "lips").
  parse = name:
    let stem  = lib.removeSuffix ".lips" name;
        parts = lib.splitString "." stem;
        n     = builtins.length parts;
    in if n == 1
       then { instance = stem; language = stem; }
       else { instance = lib.concatStringsSep "." (lib.take (n - 1) parts);
              language = builtins.elemAt parts (n - 1); };

  # Everything minted for a language sits in one folder beside the programs
  # (Lips.Identity.langDir): <dir>/<language>/.
  langDir = language: dir + "/${language}";

  # The FIRST line with a given prefix. The record embeds the mint prompt and a
  # tool transcript further down, which must never answer a header question.
  firstLine = prefix: text:
    let hit = lib.findFirst (l: lib.hasPrefix prefix l) null (lib.splitString "\n" text);
    in if hit == null then null else lib.removePrefix prefix hit;

  # The world the engine was minted into, from its committed record. Same
  # precedence as Lips.Generate.Record.recordedWorld: the `world:` pin (name
  # first, hash second), else a pre-worlds `target:` slug, else nixos -- which
  # is what a record older than both meant.
  worldOf = language:
    let genFile = langDir language + "/${language}.generation";
        text = if builtins.pathExists genFile then builtins.readFile genFile else "";
        pinned = firstLine "world: " text;
        legacy = firstLine "target: " text;
    in if pinned != null then builtins.head (lib.splitString " " pinned)
       else if legacy != null then legacy
       else "nixos";

  # Which flake output a world's modules belong under: the world file's own
  # word for it. Read from the copy beside the engine, never from a list here,
  # so a world nobody foresaw needs no edit in this file.
  moduleAttrOf = language:
    let wFile = langDir language + "/${worldOf language}.world";
        attr = if builtins.pathExists wFile
               then firstLine "module-attr: " (builtins.readFile wFile)
               else null;
    in if attr != null then attr
       else throw ("lips.modulesFromDir: " + toString wFile + " is missing or states no"
                    + " module-attr:, so nothing says which output "
                    + language + " belongs under.");

  # Reproduce the on-disk shape in the build cwd -- program at top level, engine
  # and artifacts in the language folder -- so `lips compile` finds them by the
  # same paths and stages the artifacts itself into $out/artifacts.
  realize = name: p:
    let artifactsSrc = langDir p.language + "/artifacts";
        hasArtifacts = builtins.pathExists artifactsSrc;
    in pkgs.runCommand "lips-${p.instance}-module" { } ''
      mkdir -p ${p.language}
      cp ${dir + "/${name}"} ${name}
      cp ${langDir p.language + "/${p.language}.lang"} ${p.language}/${p.language}.lang
      # The .generation record and the world file travel too: the record names
      # the world, the world file IS the physics compile assembles the flake
      # from. Without them compile refuses, which is the point -- a compiled
      # directory can only come from the world its engine was minted into.
      cp ${langDir p.language + "/${p.language}.generation"} ${p.language}/${p.language}.generation
      cp ${langDir p.language + "/${worldOf p.language}.world"} ${p.language}/${worldOf p.language}.world
      ${lib.optionalString hasArtifacts "cp -r ${artifactsSrc} ${p.language}/artifacts"}
      # --no-contract: the behavioral gate evaluates the realized module with
      # nix, which a compile INSIDE a nix build cannot do (no recursive nix). The
      # contract is checked in the repo, by `lips check` / `just check-expect`;
      # here the skip is stated rather than implied by not staging the .expect.
      ${lips}/bin/lips compile --no-contract --out "$out" ${name}
    '';

  built = lib.mapAttrs' (name: _:
    let p = parse name;
    in lib.nameValuePair p.instance {
         moduleAttr = moduleAttrOf p.language;
         module = realize name p;   # the compiled DIRECTORY (artifact.nix lives beside default.nix in it)
       }) entries;

  # The PUBLIC value must be importable exactly as the README shows it
  # (`imports = [ lips.nixosModules.<instance> ]`), and a bare derivation is
  # NOT: NixOS's own module loader (nixpkgs lib/modules.nix's `loadModule`)
  # checks `isFunction`, then `isAttrs` (true for a derivation, which is an
  # attrset with no `_type`, so `m._type or "module" == "module"` is true and
  # the DERIVATION ITSELF is read as literal module content -- its own
  # `outPath`/`drvPath`/build-system bookkeeping attrs surface as bogus
  # options, e.g. "the option `...__ignoreNulls` does not exist"), and only
  # falls through to `import (toString m)` for a value that is neither. This
  # is exactly the workaround this repo's OWN `vm-smoke`/`artifact-vm` checks
  # already carry (`imports = [ "${realized}" ]`, commented there for the same
  # reason) -- it was never propagated to this public helper, so any external
  # consumer following the README literally hit the bug first, on a real
  # machine, ahead of any check here. A STRING (Nix's `import` resolves a
  # directory string to its `default.nix`, same as a literal `./dir` path) is
  # neither `isFunction` nor `isAttrs` nor `isList`, so it takes that branch
  # correctly. String interpolation of an already-string value is a no-op, so
  # every internal consumer of `nixosModules`/`homeManagerModules` (the eval
  # and build checks below, which read `${p}/default.nix` and `${p}/artifact.nix`)
  # is unaffected: they see the identical text either way.
  byAttr = a: lib.mapAttrs (_: v: "${v.module}")
                 (lib.filterAttrs (_: v: v.moduleAttr == a) built);
  # Exactly the outputs the programs in this directory call for: an attribute
  # exists when some engine was minted into a world that names it. A consumer
  # reading an absent one gets nix's own "attribute missing", which says the
  # truth (there is no such program here) rather than an empty set that reads
  # as "none of yours built".
in lib.genAttrs (lib.unique (map (v: v.moduleAttr) (lib.attrValues built))) byAttr
