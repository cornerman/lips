# Expose lips programs in a directory as flake module outputs, grouped by the
# world each engine was minted into. A language holds one folder per world, so
# an instance appears under EVERY world it was minted for: the output NAME comes
# from that world file's own `module-attr:` header, so a house world lands under
# its own attribute with no edit here, exactly as nixos lands under
# nixosModules. The realized module is DERIVED by running `lips compile` in a
# derivation (offline, deterministic); the program, the shared grammar and the
# world's own files are the only committed inputs. Each output value is the
# compiled DIRECTORY (default.nix + a staged artifacts/ tree); `imports` accepts
# the directory and resolves its default.nix.
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
  # (Lips.Identity.langDir): <dir>/<language>/, with one subfolder per world.
  langDir = language: dir + "/${language}";
  worldDir = language: world: langDir language + "/${world}";

  # The FIRST line with a given prefix. The record embeds the mint prompt and a
  # tool transcript further down, which must never answer a header question.
  firstLine = prefix: text:
    let hit = lib.findFirst (l: lib.hasPrefix prefix l) null (lib.splitString "\n" text);
    in if hit == null then null else lib.removePrefix prefix hit;

  # The worlds a language holds, found by looking -- the Nix twin of
  # Lips.Language.mintedWorlds, and keyed on the same marker: a subdirectory
  # carrying this language's rules. out/ and artifacts/ are excluded for free.
  worldsOf = language:
    let d = langDir language;
        subdirs = lib.attrNames (lib.filterAttrs (_: t: t == "directory")
                                   (if builtins.pathExists d then builtins.readDir d else { }));
    in lib.filter (w: builtins.pathExists (worldDir language w + "/${language}.rules")) subdirs;

  # Which flake output a world's modules belong under: the world file's own
  # word for it. Read from the copy beside the engine, never from a list here,
  # so a world nobody foresaw needs no edit in this file.
  moduleAttrOf = language: world:
    let wFile = worldDir language world + "/${world}.world";
        attr = if builtins.pathExists wFile
               then firstLine "module-attr: " (builtins.readFile wFile)
               else null;
    in if attr != null then attr
       else throw ("lips.modulesFromDir: " + toString wFile + " is missing or states no"
                    + " module-attr:, so nothing says which output "
                    + language + " belongs under.");

  # Reproduce the on-disk shape in the build cwd -- program at top level, the
  # shared grammar in the language folder, this world's files in its own -- so
  # `lips compile` finds them by the same paths and stages the artifacts itself.
  # One world is staged, so compile writes exactly one world's directory.
  realize = name: p: world:
    let artifactsSrc = langDir p.language + "/artifacts";
        hasArtifacts = builtins.pathExists artifactsSrc;
        genFile = worldDir p.language world + "/${p.language}.generation";
    in pkgs.runCommand "lips-${p.instance}-${world}-module" { } ''
      mkdir -p ${p.language}/${world}
      cp ${dir + "/${name}"} ${name}
      cp ${langDir p.language + "/${p.language}.grammar"} ${p.language}/${p.language}.grammar
      cp ${worldDir p.language world + "/${p.language}.rules"} ${p.language}/${world}/${p.language}.rules
      # The .generation record and the world file travel too: the record names
      # the world, the world file IS the physics compile assembles the flake
      # from. Without them compile refuses, which is the point -- a compiled
      # directory can only come from the world its engine was minted into.
      ${lib.optionalString (builtins.pathExists genFile)
          "cp ${genFile} ${p.language}/${world}/${p.language}.generation"}
      cp ${worldDir p.language world + "/${world}.world"} ${p.language}/${world}/${world}.world
      ${lib.optionalString hasArtifacts "cp -r ${artifactsSrc} ${p.language}/artifacts"}
      # --no-contract: the behavioral gate evaluates the realized module with
      # nix, which a compile INSIDE a nix build cannot do (no recursive nix). The
      # contract is checked in the repo, by `lips check` / `just check-expect`;
      # here the skip is stated rather than implied by not staging the .expect.
      ${lips}/bin/lips compile --no-contract --out "$out" ${name}
    '';

  # One entry per (instance, world) pair: the same program minted into two
  # worlds is two modules, under two attributes.
  built = lib.concatMap (name:
    let p = parse name;
    in map (world: {
         instance = p.instance;
         moduleAttr = moduleAttrOf p.language world;
         # compile splits its output directory by world, so the module sits one
         # level in, under the world's own name.
         module = "${realize name p world}/${world}";
       }) (worldsOf p.language)) (lib.attrNames entries);

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
  byAttr = a: lib.listToAttrs (map (v: lib.nameValuePair v.instance v.module)
                                 (lib.filter (v: v.moduleAttr == a) built));
  # Exactly the outputs the programs in this directory call for: an attribute
  # exists when some engine was minted into a world that names it. A consumer
  # reading an absent one gets nix's own "attribute missing", which says the
  # truth (there is no such program here) rather than an empty set that reads
  # as "none of yours built".
in lib.genAttrs (lib.unique (map (v: v.moduleAttr) built)) byAttr
