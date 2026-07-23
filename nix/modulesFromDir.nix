# Expose lips programs in a directory as flake module outputs, labeled by the
# world each engine was minted for. The label is read from the committed
# <language>.generation record (the `target:` line), so a program lands under
# nixosModules or homeManagerModules automatically. The realized module is
# DERIVED by running `lips print` in a derivation (offline, deterministic); the
# program and its .lang are the only committed inputs. Each output value is the
# PATH to the realized module.nix (imports accepts a path), inside a directory
# that also stages the program's artifacts/ tree when it has one, so a relative
# `src = ./artifacts/<name>` resolves on import.
{ pkgs, lib, lips, dir }:
let
  entries = lib.filterAttrs (n: _: lib.hasSuffix ".lips" n) (builtins.readDir dir);

  # <instance>.<language>.lips -> { instance, language }.
  parse = name:
    let parts = lib.splitString "." name;
    in { instance = builtins.elemAt parts 0;
         language = builtins.elemAt parts 1; };

  # The world the engine was minted for, from its committed .generation record.
  # No record, or no target line (an engine minted before targets): nixos.
  targetOf = language:
    let genFile = dir + "/${language}.generation";
    in if builtins.pathExists genFile
          && lib.hasInfix "target: home-manager" (builtins.readFile genFile)
       then "home-manager" else "nixos";

  realize = name: p:
    let artifactsSrc = dir + "/${name}.artifacts";
        hasArtifacts = builtins.pathExists artifactsSrc;
    in pkgs.runCommand "lips-${p.instance}-module" { } ''
      cp ${dir + "/${name}"} ${name}
      cp ${dir + "/${p.language}.lang"} ${p.language}.lang
      mkdir -p "$out"
      ${lips}/bin/lips print ${name} > "$out/module.nix"
      ${lib.optionalString hasArtifacts ''
        mkdir -p "$out/artifacts"
        cp -r ${artifactsSrc}/. "$out/artifacts/"
      ''}
    '';

  built = lib.mapAttrs' (name: _:
    let p = parse name;
    in lib.nameValuePair p.instance {
         target = targetOf p.language;
         module = "${realize name p}/module.nix";
       }) entries;

  byTarget = t: lib.mapAttrs (_: v: v.module)
                  (lib.filterAttrs (_: v: v.target == t) built);
in {
  nixosModules = byTarget "nixos";
  homeManagerModules = byTarget "home-manager";
}
