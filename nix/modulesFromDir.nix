# Expose lips programs in a directory as flake module outputs, labeled by the
# world each engine was minted for. The label is read from the committed
# <language>/<language>.generation record (the `target:` line), so a program lands under
# nixosModules or homeManagerModules automatically. The realized module is
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

  # The world the engine was minted for, from its committed .generation record.
  # The slug is read, not tested against a list of known worlds, so a target
  # added to Lips.Nix.Target needs no edit here beyond its output name below.
  # The FIRST "target: " line is the record's own field; the mint prompt quoted
  # further down the same file must not be able to answer this question.
  # No record, or no target line (an engine minted before targets): nixos.
  targetOf = language:
    let genFile = langDir language + "/${language}.generation";
        hit = if builtins.pathExists genFile
              then lib.findFirst (l: lib.hasPrefix "target: " l) null
                     (lib.splitString "\n" (builtins.readFile genFile))
              else null;
    in if hit == null then "nixos" else lib.removePrefix "target: " hit;

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
      # The .generation record travels too: it names the world the engine was
      # minted for, and compile reads it to decide which flake the compiled
      # directory gets. Without it every world would silently compile as the
      # default one and the emitted flake would offer rungs that cannot work.
      cp ${langDir p.language + "/${p.language}.generation"} ${p.language}/${p.language}.generation
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
         target = targetOf p.language;
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
  byTarget = t: lib.mapAttrs (_: v: "${v.module}")
                  (lib.filterAttrs (_: v: v.target == t) built);
in {
  nixosModules = byTarget "nixos";
  homeManagerModules = byTarget "home-manager";
  # kubenix has no module-output convention of its own, so lips names one, the
  # same name the compiled flake uses (Lips.Nix.Flake.moduleOutput).
  kubenixModules = byTarget "kubenix";
  # Same for terranix: lips names the output, matching the compiled flake.
  terranixModules = byTarget "terranix";
}
