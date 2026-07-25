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

  # <instance>.<language>.lips -> { instance, language }.
  parse = name:
    let parts = lib.splitString "." name;
    in { instance = builtins.elemAt parts 0;
         language = builtins.elemAt parts 1; };

  # Everything minted for a language sits in one folder beside the programs
  # (Lips.Identity.langDir): <dir>/<language>/.
  langDir = language: dir + "/${language}";

  # The world the engine was minted for, from its committed .generation record.
  # No record, or no target line (an engine minted before targets): nixos.
  targetOf = language:
    let genFile = langDir language + "/${language}.generation";
    in if builtins.pathExists genFile
          && lib.hasInfix "target: home-manager" (builtins.readFile genFile)
       then "home-manager" else "nixos";

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
      ${lib.optionalString hasArtifacts "cp -r ${artifactsSrc} ${p.language}/artifacts"}
      ${lips}/bin/lips compile --out "$out" ${name}
    '';

  built = lib.mapAttrs' (name: _:
    let p = parse name;
    in lib.nameValuePair p.instance {
         target = targetOf p.language;
         module = realize name p;   # the compiled directory (imports resolves default.nix)
       }) entries;

  byTarget = t: lib.mapAttrs (_: v: v.module)
                  (lib.filterAttrs (_: v: v.target == t) built);
in {
  nixosModules = byTarget "nixos";
  homeManagerModules = byTarget "home-manager";
}
