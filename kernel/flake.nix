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
      } // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux) {
        # The realization smoke test (spec section 12.4, "realized ... on a
        # real machine"; ledger section 13): a committed Solution is realized
        # deterministically (no model) and the resulting module must be an
        # ORDINARY NixOS module -- imported beside stock modules, booted in a
        # VM, its units present and its timer live. This pins the coexistence
        # defense (one Solution = one importable module) as a permanent check,
        # not a one-off demo.
        vm-smoke =
          let
            lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            # Deterministic tail only: crystallize + run the committed example
            # with its committed minted language. No AI in this derivation.
            realized = pkgs.runCommand "lips-backup-module.nix" { } ''
              cp ${./examples/backup.loose} backup.loose
              cp ${./examples/backup.loose.lang} backup.loose.lang
              ${lips}/bin/lips run backup.loose > "$out"
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-realized-module-boots";
            nodes.machine = { ... }: {
              # "${...}": import the derivation's OUTPUT PATH; a bare derivation
              # in `imports` is misread as an inline attrset module.
              imports = [ "${realized}" ];
            };
            testScript = ''
              machine.wait_for_unit("multi-user.target")
              # The minted timer is live in a booted system (unit names come
              # from the stock restic module the engine targets).
              machine.wait_for_unit("restic-backups-ledger.timer")
              # Every program line is witnessed in the booted system:
              # line 1 (destination, cadence)
              machine.succeed(
                  "systemctl cat restic-backups-ledger.service | grep -F 'RESTIC_REPOSITORY=/backup/ledger'"
              )
              machine.succeed(
                  "systemctl cat restic-backups-ledger.timer | grep -F 'OnCalendar=daily'"
              )
              # line 1 (source; the restic module routes paths through a
              # staticPaths store file that pre-start cats into the includes)
              machine.succeed("grep -lF '/var/lib/ledger' /nix/store/*-staticPaths")
              # line 2 (retention)
              machine.succeed(
                  "systemctl cat restic-backups-ledger.service | grep -F -- '--keep-daily 14'"
              )
              # line 3 (credentials)
              machine.succeed(
                  "systemctl cat restic-backups-ledger.service | grep -F 'EnvironmentFile=/etc/ledger-backup.env'"
              )
            '';
          };
      });
    };
}
