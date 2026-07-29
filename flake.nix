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
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck p.aeson p.optparse-applicative ]);
    in
    {
      # Everything a developer needs: the compiler for the suite, and just
      # as the command index (see justfile at the repo root).
      devShells = forAll (pkgs: {
        default = pkgs.mkShell { packages = [ (ghc pkgs) pkgs.just ]; };
      });

      # The reference `lips` CLI, built from the deliverable in kernel/.
      # `nix run . -- compile examples/ledger.backup.lips`.
      packages = forAll (pkgs: {
        default = pkgs.runCommand "lips"
          { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper pkgs.installShellFiles ]; } ''
          cp -r ${./kernel}/. build && cd build
          mkdir -p "$out/bin"
          ghc -Wall -isrc -iapp app/Main.hs -outputdir "$TMPDIR/o" -o "$out/bin/.lips-unwrapped"
          # generate checks minted rules against the NixOS option schema, which
          # it builds lazily from THIS pinned nixpkgs. Bake the ref as a STRING
          # (a rev, not a store path), so nixpkgs never enters the closure of
          # print/run/check; only generate resolves and evaluates it. A caller
          # may override with LIPS_OPTIONS_JSON (a prebuilt options.json).
          # --argv0 lips: getProgName (used by optparse-applicative for --help's
          # usage line AND the generated completion scripts' function/compdef
          # names) otherwise reports the wrapper's real target, .lips-unwrapped
          # -- breaking `lips <TAB>` silently (the completion function would be
          # registered under the wrong name).
          # The mint's one tool, shipped with the binary rather than installed
          # into the user's pi: lips loads it per run with `-e`, so the tool
          # exists inside a mint and nowhere else. LIPS_BIN points the extension
          # back at this same wrapper, so a lookup answers with what THIS lips
          # says, not whatever `lips` happens to be on PATH.
          install -Dm444 ${./assets/mint-tools.ts} "$out/share/lips/mint-tools.ts"
          makeWrapper "$out/bin/.lips-unwrapped" "$out/bin/lips" \
            --argv0 lips \
            --set-default LIPS_NIXPKGS_FLAKE "github:NixOS/nixpkgs/${nixpkgs.rev}" \
            --set-default LIPS_HM_FLAKE "github:nix-community/home-manager/${home-manager.rev}" \
            --set-default LIPS_MINT_TOOLS "$out/share/lips/mint-tools.ts" \
            --set-default LIPS_BIN "$out/bin/lips"
          # Completion scripts derive from the SAME optparse-applicative Parser
          # that parses real invocations (Lips.Cli), so they cannot drift from
          # it the way a hand-maintained static script would. Generated from
          # the just-built binary; hermetic (no network, no AI call -- these
          # flags are a pure parser-introspection path, never reaching pi).
          installShellCompletion --cmd lips \
            --bash <($out/bin/lips --bash-completion-script $out/bin/lips) \
            --zsh  <($out/bin/lips --zsh-completion-script  $out/bin/lips) \
            --fish <($out/bin/lips --fish-completion-script $out/bin/lips)
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
        # and produces an importable module path. Both worlds must be non-empty
        # and every realized module must build (test -f forces it).
        lipsModules-eval =
          let
            mods  = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            # Both worlds, so EVERY committed example is compiled by this check.
            # Forcing only nixosModules left the home-manager ones (all four
            # singleton <language>.lips programs) unevaluated, which is how a
            # broken filename rule survived here.
            paths = builtins.attrValues mods.nixosModules
                    ++ builtins.attrValues mods.homeManagerModules;
          in pkgs.runCommand "lips-modules-eval" { } ''
            test -n "${toString (builtins.attrNames mods.nixosModules)}"
            test -n "${toString (builtins.attrNames mods.homeManagerModules)}"
            ${pkgs.lib.concatMapStringsSep "\n" (p: "test -f ${p}/default.nix") paths}
            touch "$out"
          '';
        # Every artifact a committed example declares must INSTANTIATE: a green
        # `lips check` says the program's values reached the output, not that the
        # build Nix describes is well-formed. Forcing each artifact's drvPath
        # instantiates its .drv (writes it to the store) WITHOUT building it, so
        # a malformed builder or a missing arg fails here in seconds instead of at
        # the user's `nix run`. This is why lips itself does not do it: the check
        # verb stays nixpkgs-free, and only a flake already has nixpkgs.
        #
        # The compiled dirs are derivation outputs, so reading artifact.nix out of
        # them is import-from-derivation (deliberate, and cheap: each dir is one
        # offline `lips compile`).
        lipsArtifacts-eval =
          let
            mods  = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            dirs  = builtins.attrValues mods.nixosModules
                    ++ builtins.attrValues mods.homeManagerModules;
            artifactsOf = dir:
              let f = "${dir}/artifact.nix";
              in if builtins.pathExists f
                 then builtins.attrValues (import f { inherit pkgs; })
                 else [ ];
            # unsafeDiscardStringContext: we want the .drv path as TEXT (proof it
            # instantiated), not a build dependency of this check.
            drvPaths = map (d: builtins.unsafeDiscardStringContext d.drvPath)
                           (builtins.concatMap artifactsOf dirs);
          in pkgs.runCommand "lips-artifacts-eval" { } ''
            test ${toString (builtins.length drvPaths)} -gt 0
            ${pkgs.lib.concatMapStringsSep "\n" (p: "test -n '${p}'") drvPaths}
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
            # The engine lives in the language folder beside the program
            # (Lips.Identity), so reproduce that shape in the build cwd.
            realized = pkgs.runCommand "lips-backup-module" { } ''
              mkdir -p backup
              cp ${./examples/ledger.backup.lips} ledger.backup.lips
              cp ${./examples/backup/backup.lang} backup/backup.lang
              # --no-contract: the gate needs nix to evaluate the module, which
              # a compile inside a nix build has not got; `lips check` gates in
              # the repo (see just check-expect).
              ${lips}/bin/lips compile --no-contract --out "$out" ledger.backup.lips
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
              mkdir -p http
              cp ${./examples/hello.http.lips} hello.http.lips
              cp ${./examples/http/http.lang} http/http.lang
              cp -r ${./examples/http/artifacts} http/artifacts
              # --no-contract: the gate needs nix to evaluate the module, which
              # a compile inside a nix build has not got; `lips check` gates in
              # the repo (see just check-expect).
              ${lips}/bin/lips compile --no-contract --out "$out" hello.http.lips
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-artifact-service-answers";
            nodes.machine = { pkgs, ... }: {
              imports = [ "${realized}/default.nix" ];
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
