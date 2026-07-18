{
  description = "lips kernel: the decision calculus (reference implementation)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      # The kernel needs only base, containers, text; hspec + QuickCheck drive
      # the conformance suite (spec section 12).
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck ]);
    in
    {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell { packages = [ (ghc pkgs) ]; };
      });

      # The reference `lips` CLI. `nix run . -- run examples/ledger.decisions`.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips" { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          cp -r ${./.}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/lips"
        '';
      });

      # `nix flake check` compiles the calculus with -Wall and runs the suite.
      checks = forAll (pkgs: {
        kernel-tests = pkgs.runCommand "lips-kernel-tests"
          { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          cp -r ${./.}/. build && cd build
          ghc -Wall -isrc -itest test/Spec.hs -outputdir "$TMPDIR/o" -o "$TMPDIR/spec"
          "$TMPDIR/spec"
          touch "$out"
        '';
      });
    };
}
