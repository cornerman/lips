{
  description = "lips: intent as a decision base, realized deterministically as a NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # home-manager is a grounding-schema source for the home-manager target: its
  # docs-json optionsJSON is baked (as a rev string) into the binary, so only
  # generate ever resolves it; print/run/check stay nixpkgs/home-manager-free.
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager }:
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
      # `nix run . -- print examples/ledger.backup.lips`.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips" { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper ]; } ''
          cp -r ${./kernel}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/.lips-unwrapped"
          # generate checks minted rules against the NixOS option schema, which
          # it builds lazily from THIS pinned nixpkgs. Bake the ref as a STRING
          # (a rev, not a store path), so nixpkgs never enters the closure of
          # print/run/check; only generate resolves and evaluates it. A caller
          # may override with LIPS_OPTIONS_JSON (a prebuilt options.json).
          makeWrapper "$out/bin/.lips-unwrapped" "$out/bin/lips" \
            --set-default LIPS_NIXPKGS_FLAKE "github:NixOS/nixpkgs/${nixpkgs.rev}" \
            --set-default LIPS_HM_FLAKE "github:nix-community/home-manager/${home-manager.rev}"
        '';
      });

      # Expose lips programs in a directory as module outputs, labeled by the
      # world each engine was minted for (read from its .generation record).
      # Downstream: imports = [ inputs.lips.nixosModules.<instance> ] (or
      # homeManagerModules). Not per-system: it takes pkgs explicitly.
      lib.modulesFromDir = { pkgs, dir }:
        import ./nix/modulesFromDir.nix {
          inherit pkgs dir;
          lib = pkgs.lib;
          lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };

      # `nix flake check` compiles the calculus with -Wall and runs the suite.
      checks = forAll (pkgs: {
        kernel-tests = pkgs.runCommand "lips-kernel-tests"
          { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          cp -r ${./kernel}/. build && cd build
          ghc -Wall -isrc -itest test/Spec.hs -outputdir "$TMPDIR/o" -o "$TMPDIR/spec"
          "$TMPDIR/spec"
          touch "$out"
        '';
        # The module helper labels each committed example by its recorded world
        # and produces an importable module path. All current examples are
        # nixos engines, so homeManagerModules is empty; nixosModules must be
        # non-empty and every realized module must build (test -f forces it).
        lipsModules-eval =
          let
            mods  = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            paths = builtins.attrValues mods.nixosModules;
          in pkgs.runCommand "lips-modules-eval" { } ''
            test -n "${toString (builtins.attrNames mods.nixosModules)}"
            ${pkgs.lib.concatMapStringsSep "\n" (p: "test -f ${p}") paths}
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
              cp ${./examples/ledger.backup.lips} ledger.backup.lips
              cp ${./examples/backup.lang} backup.lang
              ${lips}/bin/lips print ledger.backup.lips > "$out"
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
              cp ${./examples/hello.http.lips} hello.http.lips
              cp ${./examples/http.lang} http.lang
              mkdir -p "$out/artifacts"
              ${lips}/bin/lips print hello.http.lips > "$out/module.nix"
              cp -r ${./examples/http.artifacts}/. "$out/artifacts/"
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
