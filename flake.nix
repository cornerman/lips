{
  description = "lips: intent as a decision base, realized deterministically as a NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      # The kernel needs only base, containers, text; the Generate tier adds
      # aeson (parsing pi's json event stream); hspec + QuickCheck drive the
      # conformance suite (spec section 12).
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck p.aeson ]);
    in
    {
      # Everything a developer needs: the compiler for the suite, and just
      # as the command index (see justfile at the repo root).
      devShells = forAll (pkgs: {
        default = pkgs.mkShell { packages = [ (ghc pkgs) pkgs.just ]; };
      });

      # The reference `lips` CLI, built from the deliverable in kernel/.
      # `nix run . -- print examples/backup.loose`.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips" { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          cp -r ${./kernel}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/lips"
        '';
      } // nixpkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux) {
        # The pinned NixOS option schema (search.nixos.org's optionsJSON),
        # evaluated from THIS flake's nixpkgs so it matches the nixpkgs a
        # realized module is checked against. generate reads it (via
        # LIPS_OPTIONS_JSON) to reject a minted rule that names a nonexistent
        # or mistyped option -- deduce-or-fail at the NixOS layer. Linux-only:
        # the NixOS manual does not evaluate on darwin.
        nixosOptionsJson =
          (import (nixpkgs + "/nixos") {
            system = pkgs.stdenv.hostPlatform.system;
            configuration = { };
          }).config.system.build.manual.optionsJSON;
      });

      # `nix flake check` compiles the calculus with -Wall and runs the suite.
      checks = forAll (pkgs: {
        kernel-tests = pkgs.runCommand "lips-kernel-tests"
          { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          cp -r ${./kernel}/. build && cd build
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
              ${lips}/bin/lips print backup.loose > "$out"
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

        # The artifacts proof (artifacts plan; ledger section 13): a Solution
        # whose realization BUILDS a program from generated source and runs it.
        # The committed hello-server example realizes to a module that
        # let-binds a buildGoModule derivation over the committed Go source and
        # wires ${artifact.httpserver} into a systemd service. This pins the
        # whole chain -- generated source -> Nix build -> service -> booted and
        # answering -- as a permanent check. No AI in this derivation.
        artifact-vm =
          let
            lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            # Realize into a DIRECTORY: the module plus its source tree, so the
            # module's relative `src = ./artifacts/<name>` resolves at import.
            realized = pkgs.runCommand "lips-hello-module" { } ''
              cp ${./examples/hello-server.loose} hello.loose
              cp ${./examples/hello-server.loose.lang} hello.loose.lang
              mkdir -p "$out/artifacts"
              ${lips}/bin/lips print hello.loose > "$out/module.nix"
              cp -r ${./examples/hello-server.loose.artifacts}/. "$out/artifacts/"
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-artifact-service-answers";
            nodes.machine = { pkgs, ... }: {
              imports = [ "${realized}/module.nix" ];
              environment.systemPackages = [ pkgs.curl ];
            };
            testScript = ''
              machine.wait_for_unit("multi-user.target")
              # The service built from generated Go source is up and listening.
              machine.wait_for_unit("hello.service")
              machine.wait_for_open_port(8080)
              # It answers with the program's text (the built artifact runs).
              machine.succeed("curl -s http://localhost:8080/ | grep -F 'hello from lips'")
            '';
          };
      });
    };
}
