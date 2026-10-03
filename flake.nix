{
  description = "lips: intent as a decision base, realized deterministically as a NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # home-manager is a grounding-schema source for the home-manager target: its
  # docs-json optionsJSON is baked (as a rev string) into the binary, so only
  # generate ever resolves it; print/run/check stay nixpkgs/home-manager-free.
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";
  # kubenix is the grounding-schema source for the kubenix target. It ships no
  # options document, so lips builds one with nixosOptionsDoc over an empty
  # kubenix evaluation; the rev is baked as a string, like the other two worlds,
  # so only generate ever resolves it.
  inputs.kubenix.url = "github:hall/kubenix";
  inputs.kubenix.inputs.nixpkgs.follows = "nixpkgs";
  # terranix is the grounding-schema source for the terranix target. Its own
  # lib.terranixOptions documents a USER's modules (it deletes resource, data,
  # provider and every other core namespace), so lips evaluates terranix's core
  # modules itself; the rev is baked as a string, like the other worlds.
  inputs.terranix.url = "github:terranix/terranix";
  inputs.terranix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager, kubenix, terranix }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
      # The kernel needs only base, containers, text; the Generate tier adds
      # aeson (parsing pi's json event stream); hspec + QuickCheck drive the
      # conformance suite (spec section 12).
      # file-embed: the mint prompt lives as markdown under assets/mint/ and the
      # worlds as data under assets/worlds/, both embedded at compile time (see
      # kernel/src/Lips/Generate/Minting.hs and Lips/World/Builtin.hs).
      ghc = pkgs: pkgs.haskellPackages.ghcWithPackages (p: [ p.hspec p.QuickCheck p.aeson p.optparse-applicative p.file-embed ]);
      # The VS Code client, as an installable extension package.
      #
      # VS Code will not start a language server from settings: a client must be
      # launched by an extension, and a language id no extension declares falls
      # back to plaintext (microsoft/vscode#194759). So this exists, and it is
      # deliberately the thinnest thing that can: it declares the `lips`
      # language for `.lips` and spawns `lips lsp` over stdio. Every capability
      # lives in the server, which is why the extension has no reason to change
      # as lips grows.
      #
      # It VERSIONS WITH THE PROTOCOL it speaks, which is why it ships here and
      # not in a consumer's config: a flake sees only its own git-tracked files,
      # so a downstream derivation could not read editors/vscode/ without a
      # second input pointing back at this same checkout.
      #
      # `lips` itself is NOT a dependency of this package: the extension spawns
      # whatever `lips` the user's PATH provides, so upgrading lips moves the
      # server without rebuilding the client.
      vscodeExtension = pkgs: pkgs.buildNpmPackage {
        pname = "vscode-lips";
        version = "0.0.1";
        src = ./editors/vscode;
        # Regenerate after any package-lock.json change:
        #   nix run nixpkgs#prefetch-npm-deps -- editors/vscode/package-lock.json
        npmDepsHash = "sha256-L2HZ1rHLwbmPumdDlLy+OdIlcComrsOlRWtgKTz8jDs=";
        # There is nothing to compile: the extension is plain CommonJS, and a
        # bundler would only add a build step and a devDependency to maintain.
        dontNpmBuild = true;
        # The layout home-manager's programs.vscode (and `code
        # --extensions-dir`) reads: one directory per extension, named
        # <publisher>.<name>, holding the manifest, the entry point and its
        # runtime deps.
        installPhase = ''
          runHook preInstall
          dir="$out/share/vscode/extensions/lips.lips"
          mkdir -p "$dir"
          cp package.json extension.js "$dir/"
          cp -r node_modules "$dir/"
          runHook postInstall
        '';
        # What an installer reads off the derivation: nixpkgs'
        # vscode-utils.toExtensionJson (which home-manager's programs.vscode
        # uses to write extensions.json) takes the id and publisher from HERE,
        # not from package.json -- and VS Code 1.74+ lists only what
        # extensions.json names, so an extension missing these is installed and
        # invisible.
        passthru = {
          vscodeExtUniqueId = "lips.lips";
          vscodeExtPublisher = "lips";
          vscodeExtName = "lips";
        };
      };
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
        vscode-extension = vscodeExtension pkgs;
        default = pkgs.runCommand "lips"
          { nativeBuildInputs = [ (ghc pkgs) pkgs.makeWrapper pkgs.installShellFiles ]; } ''
          # assets/ is copied as build's SIBLING (not build/assets/), so the
          # embedStringFile path "../assets/..." in Minting.hs/World/Builtin.hs resolves
          # the same way here as it does from kernel/ under a direct `ghc`
          # invocation, where ".." is likewise the repo root.
          mkdir -p assets && cp -r ${./assets}/. assets && cp -r ${./kernel}/. build && cd build
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
            --set-default LIPS_KUBENIX_FLAKE "github:hall/kubenix/${kubenix.rev}" \
            --set-default LIPS_TERRANIX_FLAKE "github:terranix/terranix/${terranix.rev}" \
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
        # The kubenix world file's schema slot reshapes kubenix's option document
        # with jq (re-key the api.resources tree onto the alias programs write,
        # unwrap `null or X` optionals, drop the inner nodes whose children carry
        # the fields). That jq used to be Haskell the suite covered; as data in a
        # world file, nothing else would ever run it -- grounding happens only at
        # generate, which CI never does, so a wrong reshaping would surface at
        # some author's next kubenix mint instead of here.
        #
        # The slot is read out of the world file rather than restated, so the
        # check judges exactly what generate will run. Both holes are filled the
        # way a pure evaluation must: the pinned input's own rev, and this
        # system's name (there is no builtins.currentSystem in pure eval, which
        # is precisely why the slot carries a <system> hole).
        kubenix-schema =
          let
            raw = builtins.readFile ./assets/worlds/kubenix.world;
            afterMarker = builtins.elemAt (builtins.split "--- schema ---\n" raw) 2;
            slot = builtins.head (builtins.split "\n--- " afterMarker);
            expr = builtins.replaceStrings
              [ "<flakeref>" "<system>" ]
              [ "github:hall/kubenix/${kubenix.rev}" "\"${pkgs.stdenv.hostPlatform.system}\"" ]
              slot;
            schema = import (builtins.toFile "kubenix-schema.nix" expr);
          in pkgs.runCommand "lips-kubenix-schema"
            { nativeBuildInputs = [ pkgs.jq ]; } ''
            # A resource field grounds under the alias path, with its optional
            # unwrapped to the scalar type a rule is checked against.
            test "$(jq -r '."kubernetes.resources.deployments.<name>.spec.replicas".type' ${schema})" \
              = "signed integer"
            # An optional LIST stays a list. The Haskell this replaced read
            # "null or (list of signed integer)" as a plain integer (its scalar
            # test matched the substring), so 78 fields refused a correct list.
            test "$(jq -r '."kubernetes.resources.apps.v1.Deployment.<name>.spec.template.spec.securityContext.supplementalGroups".type' ${schema})" \
              = "list of signed integer"
            # The typed spelling is MOVED, not copied: one path grounds.
            jq -e '[to_entries[] | select(.key | startswith("kubernetes.api.resources"))] | length == 0' ${schema} > /dev/null
            # Inner nodes are gone, so a misspelled field below one cannot be
            # admitted by its parent's declaration.
            jq -e 'has("kubernetes.resources.deployments.<name>.spec") | not' ${schema} > /dev/null
            touch "$out"
          '';
        # Every Nix-bearing slot of every shipped world, through nix's own
        # parser -- and one deliberately broken house world, to show a defect is
        # caught and reported against the world FILE. The hspec suite cannot run
        # either half: its own build sandbox has no nix, so it covers only which
        # text nix is handed. Without this check, a wrapper that stopped
        # matching how flakeText embeds a slot would surface as a syntax error
        # in somebody's generated flake.nix.
        world-slots = pkgs.runCommand "lips-world-slots"
          { nativeBuildInputs = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default pkgs.nix ]; } ''
          export HOME="$TMPDIR"
          cd "$TMPDIR"
          lips world --check
          cat > house-broken.world <<'EOF'
          format: 1
          world: house-broken
          module-attr: houseModules
          --- preamble ---
          prose
          --- schema ---
          let x = ;
          in x
          EOF
          if lips world --check house-broken > refusal 2>&1; then
            echo "a world whose schema does not parse was accepted:"; cat refusal; exit 1
          fi
          # The line and column are the world file's own, which is the whole
          # point of slicing a slot line-aligned.
          grep -q "schema slot is not valid Nix" refusal
          grep -q "house-broken.world:7:9" refusal
          # lips writes a world's schema input itself, at the record's pin, so
          # an inputs slot declaring it too is refused, whatever its spelling.
          cat > house-dup.world <<'EOF'
          format: 3
          world: house-dup
          module-attr: houseModules
          schema-input: kubenix github:hall/kubenix
          --- preamble ---
          prose
          --- schema ---
          null
          --- inputs ---
            inputs = { kubenix.url = "github:hall/kubenix"; };
          EOF
          if lips world --check house-dup > refusal 2>&1; then
            echo "a world declaring its schema input twice was accepted:"; cat refusal; exit 1
          fi
          grep -q "its inputs slot declares kubenix" refusal
          touch "$out"
        '';
        kernel-tests = pkgs.runCommand "lips-kernel-tests"
          { nativeBuildInputs = [ (ghc pkgs) ]; } ''
          mkdir -p assets && cp -r ${./assets}/. assets && cp -r ${./kernel}/. build && cd build
          ghc -Wall -isrc -itest test/Spec.hs -outputdir "$TMPDIR/o" -o "$TMPDIR/spec"
          "$TMPDIR/spec"
          touch "$out"
        '';
        # The module helper labels each committed example by its recorded world
        # and produces an importable module path. Both worlds must be non-empty,
        # every realized module must build (test -f forces it), and -- the part
        # that actually caught a real bug -- every one must import CORRECTLY
        # through a real evalModules, not just exist on disk. `test -f` alone
        # cannot see that: a bare derivation in `imports` is misread by NixOS's
        # module loader as literal module content (its own `outPath`/`drvPath`
        # bookkeeping attrs surface as bogus options), which this check missed
        # for as long as `nixosModules`/`homeManagerModules` exposed a bare
        # derivation instead of a string (see modulesFromDir.nix's byTarget
        # comment) -- caught only by a real deployment, on a real machine,
        # nesting a home-manager module inside a NixOS host. Instantiate (never
        # build, same technique as lipsArtifacts-eval's drvPath-forcing) a real
        # nixosSystem/homeManagerConfiguration per instance, exactly the way an
        # external consumer's flake would, over the PUBLIC value this helper
        # hands out -- not a hand-rolled workaround local to this file.
        lipsModules-eval =
          let
            mods  = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            # EVERY world attribute the helper produced, found by looking rather
            # than by name, so every committed example is compiled by this check
            # -- a house world (examples/nono.world's nonoModules) included.
            # Naming the four shipped attributes left nonoModules unevaluated,
            # as forcing only nixosModules once left the home-manager ones.
            paths = builtins.concatMap builtins.attrValues (builtins.attrValues mods);
            # A real nixosSystem's system.build.toplevel forces the generic
            # "is this bootable" assertions (a root filesystem, a bootloader),
            # which no committed example states an opinion on -- so a minimal
            # stub module supplies them, purely as literals (never built, only
            # instantiated, so none of this touches a real disk).
            hardwareStub = {
              fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
              boot.loader.grub.devices = [ "/dev/sda" ];
              system.stateVersion = nixpkgs.lib.trivial.release;
            };
            nixosDrvPaths = map
              (p: (nixpkgs.lib.nixosSystem {
                     system = pkgs.stdenv.hostPlatform.system;
                     modules = [ p hardwareStub ];
                   }).config.system.build.toplevel.drvPath)
              (builtins.attrValues mods.nixosModules);
            # Same idea as hardwareStub: the generic "whose home is this"
            # boilerplate every home-manager config needs, which no committed
            # example states an opinion on either.
            homeStub = {
              home.username = "lips-modules-eval";
              home.homeDirectory = "/home/lips-modules-eval";
              home.stateVersion = nixpkgs.lib.trivial.release;
            };
            homeDrvPaths = map
              (p: (home-manager.lib.homeManagerConfiguration {
                     inherit pkgs;
                     modules = [ p homeStub ];
                   }).activationPackage.drvPath)
              (builtins.attrValues mods.homeManagerModules);
            # A kubenix module has no machine and no home: what it MEANS is the
            # manifest it renders, so instantiating that rendering is the same
            # proof for this world -- and a strong one, since kubenix refuses an
            # unknown or mistyped Kubernetes field at evaluation.
            kubenixDrvPaths = map
              (p: (kubenix.evalModules.${pkgs.stdenv.hostPlatform.system} {
                     module = { kubenix, ... }: {
                       imports = [ kubenix.modules.k8s "${p}" ];
                     };
                   }).config.kubernetes.resultYAML.drvPath)
              (builtins.attrValues mods.kubenixModules);
            # A terranix module means the config.tf.json it renders, so
            # instantiating that render is this world's proof. Weaker than
            # kubenix's: terranix's namespaces are free-form, so this catches a
            # module that fails to evaluate or to serialize, never a wrong field.
            terranixDrvPaths = map
              (p: (terranix.lib.terranixConfiguration {
                     inherit pkgs;
                     modules = [ "${p}" ];
                   }).drvPath)
              (builtins.attrValues mods.terranixModules);
            # unsafeDiscardStringContext: proof of instantiation as TEXT, not a
            # build dependency of this check (lipsArtifacts-eval's own idiom).
            allDrvPaths = map builtins.unsafeDiscardStringContext
              (nixosDrvPaths ++ homeDrvPaths ++ kubenixDrvPaths ++ terranixDrvPaths);
          in pkgs.runCommand "lips-modules-eval" { } ''
            test -n "${toString (builtins.attrNames mods.nixosModules)}"
            test -n "${toString (builtins.attrNames mods.homeManagerModules)}"
            test -n "${toString (builtins.attrNames mods.kubenixModules)}"
            test -n "${toString (builtins.attrNames mods.terranixModules)}"
            ${pkgs.lib.concatMapStringsSep "\n" (p: "test -f ${p}/default.nix") paths}
            ${pkgs.lib.concatMapStringsSep "\n" (d: "test -n '${d}'") allDrvPaths}
            touch "$out"
          '';
        # Every world's own GATE, BUILT for every committed example whose world
        # declares one (packages.<system>.gate in its compiled flake). Generate
        # builds the same attribute before it accepts an engine; this re-runs it
        # against the corpus as it stands, so a lips change that alters a render
        # after the mint is caught here, not by a user's build. Found by looking:
        # every compiled directory of every world attribute, so no world is
        # named. The compiled flake's outputs function is called with THIS
        # flake's inputs (its pinned nixpkgs, the pin generate builds against),
        # picked by the argument names it asks for; an input it asks for that
        # lips does not have fails the evaluation loudly. Import-from-derivation,
        # as lipsArtifacts-eval already is.
        lipsWorld-gates =
          let
            mods = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            system = pkgs.stdenv.hostPlatform.system;
            dirs = builtins.concatMap builtins.attrValues (builtins.attrValues mods);
            outputsOf = dir:
              let
                flake = import "${dir}/flake.nix";
                outs = flake.outputs (builtins.intersectAttrs
                  (builtins.functionArgs flake.outputs)
                  { self = outs; inherit nixpkgs home-manager kubenix terranix; });
              in outs;
            gateOf = dir:
              let ps = (outputsOf dir).packages.${system} or { };
              in if ps ? gate then [ ps.gate ] else [ ];
            gates = builtins.concatMap gateOf dirs;
          in pkgs.runCommand "lips-world-gates" { } ''
            # At least one, or this check passes by judging nothing.
            test ${toString (builtins.length gates)} -gt 0
            ${pkgs.lib.concatMapStringsSep "\n" (g: "test -e ${g}") gates}
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
        # A path INSIDE a build must exist. Instantiating (above) proves the build
        # is well-formed; it says nothing about what the build produces, and the
        # name of a binary is decided by the source, not by the derivation. An http
        # mint that left `module app` in go.mod shipped a unit whose
        # ExecStart = "${artifact.hello}/bin/hello" named a file the build does not
        # contain -- past `lips check`, past the eval check above, and only
        # discoverable by running it. So: build every committed artifact and assert
        # every path the module names under it really is there.
        lipsArtifacts-build =
          let
            mods  = self.lib.modulesFromDir { inherit pkgs; dir = ./examples; };
            dirs  = builtins.attrValues mods.nixosModules
                    ++ builtins.attrValues mods.homeManagerModules;
            # Every ${artifact.<name>}<suffix> the realized module interpolates.
            # A bare `artifact.<name>` list element (a package) has no suffix and
            # is covered by building it, which this check does for every artifact.
            refsOf = dir:
              let
                arts = import "${dir}/artifact.nix" { inherit pkgs; };
                text = builtins.readFile "${dir}/default.nix";
                parts = builtins.split "artifact\\.([a-zA-Z0-9_-]+)}(/[^\"[:space:]]*)?" text;
                hit = m: {
                  drv = arts.${builtins.elemAt m 0};
                  suffix = let sfx = builtins.elemAt m 1; in if sfx == null then "" else sfx;
                };
              in map hit (builtins.filter builtins.isList parts);
            refs = builtins.concatMap
              (d: if builtins.pathExists "${d}/artifact.nix" then refsOf d else [ ])
              dirs;
            allArtifacts = builtins.concatMap
              (d: if builtins.pathExists "${d}/artifact.nix"
                  then builtins.attrValues (import "${d}/artifact.nix" { inherit pkgs; })
                  else [ ])
              dirs;
          in pkgs.runCommand "lips-artifacts-build" { } ''
            test ${toString (builtins.length allArtifacts)} -gt 0
            # Building every artifact is this derivation's own dependency graph.
            ${pkgs.lib.concatMapStringsSep "\n" (a: "test -d ${a}") allArtifacts}
            ${pkgs.lib.concatMapStringsSep "\n"
                (r: "test -e ${r.drv}${r.suffix} || { echo 'the module names ${r.suffix} inside ${r.drv}, which the build does not contain'; exit 1; }")
                refs}
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
              mkdir -p backup/nixos
              cp ${./examples/ledger.backup.lips} ledger.backup.lips
              # The shared grammar sits at the language level, the world's rules
              # in its own folder: the shape Lips.Identity names and compile reads.
              cp ${./examples/backup/backup.grammar} backup/backup.grammar
              cp ${./examples/backup/nixos/backup.rules} backup/nixos/backup.rules
              # Staged for the same reason as the artifact check below, so both
              # look like a real language folder even though this one bakes no
              # source and so never consults it.
              cp ${./examples/backup/nixos/backup.generation} backup/nixos/backup.generation
              # The world file travels too: it IS the physics compile assembles
              # the flake from, and compile requires the copy the record names.
              cp ${./examples/backup/nixos/nixos.world} backup/nixos/nixos.world
              # --no-contract: the gate needs nix to evaluate the module, which
              # a compile inside a nix build has not got; `lips check` gates in
              # the repo (see just check-expect).
              # compile splits its output by world, so the module lands in
              # $out/nixos; the check below imports it from there.
              ${lips}/bin/lips compile --no-contract --out "$out" ledger.backup.lips
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-realized-module-boots";
            nodes.machine = { ... }: {
              # "${...}": import the derivation's OUTPUT PATH; a bare derivation
              # in `imports` is misread as an inline attrset module.
              imports = [ "${realized}/nixos" ];
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

        # The built-program proof (artifacts plan; ledger section 13): a Solution
        # whose realization BUILDS the program it needs and runs it. The
        # committed website example realizes to a module that let-binds a derivation
        # over the clause SITE compile writes (its guile program), wires it into a
        # oneshot unit that prints the page into an nginx document root, and
        # serves it. This pins the whole chain -- rules -> built program ->
        # service -> booted and answering -- as a permanent check. No AI in this
        # derivation.
        #
        # No source tree is copied in, and that is the current state of the
        # corpus rather than an omission: no committed program carries a
        # mint-written source tree any more (the no-blob doctrine; `website` shed
        # its Go http server on 2026-08-12), so the program under test is the one
        # `compile` derives from the rules.
        website-vm =
          let
            lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            # Realize into a DIRECTORY: the module plus the site it builds, so the
            # module's relative paths resolve at import.
            realized = pkgs.runCommand "lips-website-module" { } ''
              mkdir -p website/nixos
              cp ${./examples/website.lips} website.lips
              cp ${./examples/website/website.grammar} website/website.grammar
              cp ${./examples/website/nixos/website.rules} website/nixos/website.rules
              # The generation record travels with the language, exactly as it
              # does in a real language folder: where a language BAKES source,
              # compile reads it to check the program still states the
              # specification that source was written from, and refuses rather
              # than skip when it cannot.
              cp ${./examples/website/nixos/website.generation} website/nixos/website.generation
              cp ${./examples/website/nixos/nixos.world} website/nixos/nixos.world
              # --no-contract: the gate needs nix to evaluate the module, which
              # a compile inside a nix build has not got; `lips check` gates in
              # the repo (see just check-expect).
              ${lips}/bin/lips compile --no-contract --out "$out" website.lips
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-website-answers";
            nodes.machine = { pkgs, ... }: {
              imports = [ "${realized}/nixos/default.nix" ];
              environment.systemPackages = [ pkgs.curl ];
            };
            testScript = ''
              machine.wait_for_unit("multi-user.target")
              # The port the program states, not a unit name: which units the
              # rules wire is the engine's choice and a re-mint may rename them,
              # while the port is a word of website.lips and cannot move without
              # the program moving.
              machine.wait_for_open_port(8081)
              # The page itself: the built program ran and its output became the
              # document root's index.
              machine.succeed("curl -fsS http://localhost:8081/ | grep -F '<!doctype html>'")
              # A word the program states, served over the wire. The engine's
              # page fetches its labels from this path rather than baking them
              # into the html, so this is where a program word reaches a client
              # (gap `browser-behaviour`: what the page's script then DOES with
              # it is observed by nothing).
              machine.succeed("curl -fsS http://localhost:8081/data/button/2/label | grep -F 'leeren'")
            '';
          };

        # The configuration proof for text a MINT wrote: the http language
        # spends each route line into an nginx `extraConfig` snippet, foreign
        # text no expect can read (an expect compares the option's string, not
        # what nginx does with it). Booting it and asking for every route is
        # what holds those words to the program's sentences, the way a claim
        # holds baked source. No AI in this derivation.
        nginx-vm =
          let
            lips = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            realized = pkgs.runCommand "lips-hello-module" { } ''
              mkdir -p http/nixos
              cp ${./examples/hello.http.lips} hello.http.lips
              cp ${./examples/http/http.grammar} http/http.grammar
              cp ${./examples/http/nixos/http.rules} http/nixos/http.rules
              cp ${./examples/http/nixos/http.generation} http/nixos/http.generation
              cp ${./examples/http/nixos/nixos.world} http/nixos/nixos.world
              ${lips}/bin/lips compile --no-contract --out "$out" hello.http.lips
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "lips-nginx-routes-answer";
            nodes.machine = { pkgs, ... }: {
              imports = [ "${realized}/nixos/default.nix" ];
              environment.systemPackages = [ pkgs.curl ];
            };
            testScript = ''
              machine.wait_for_unit("multi-user.target")
              # The program names the serving unit, and the name is realized as
              # a systemd alias on nginx, so the author's word works verbatim.
              machine.wait_for_unit("hello.service")
              machine.wait_for_open_port(8080)
              # Every route answers with the text its own line states.
              machine.succeed("curl -s http://localhost:8080/ | grep -F 'hello from lips'")
              machine.succeed("curl -s http://localhost:8080/health | grep -F 'ok'")
              machine.succeed("curl -s http://localhost:8080/version | grep -F 'lips 0.1'")
            '';
          };
      });
    };
}
