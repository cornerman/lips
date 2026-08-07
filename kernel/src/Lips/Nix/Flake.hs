{-# LANGUAGE OverloadedStrings #-}

-- | The addressable entry a @compile@ writes beside @default.nix@: a
-- @flake.nix@ whose outputs turn the compiled directory into things @nix@ can
-- run and build directly. Running a lips program is not a lips verb; @compile@
-- is the sole materialization, and every way to run is a stock @nix@ command
-- over this flake. So this module holds no run logic -- only the flake text
-- and the exact commands to print, both pure functions of the program's
-- /shape/ (its world, and whether it declares artifacts). The kernel stays
-- domain-blind; this is target-tier knowledge (Lips.Nix.*), like 'Lips.Nix.Target'.
--
-- Two axes meet here:
--
--   * artifact rungs (@exec@, @shell@): run\/build the buildable derivation
--     directly. Present only when the program declares an @artifact.\<name\>@.
--     Bare by construction -- no init runs, so no service and no service env.
--   * system rungs (@vm@, @shell@): evaluate @.\/default.nix@ through the NixOS
--     module system and take two things off that one evaluation -- boot the
--     result in QEMU (@vm@: real systemd, all services), or enter a dev shell
--     holding what the config puts on the system PATH (@shell@) -- plus one
--     such shell per unit the program adds (@service-\<unit\>@), carrying that
--     unit's @environment@, which is exactly what the bare artifact rungs
--     cannot have. A shell, never a run rung: lips does not emulate systemd,
--     so everything else a unit asks for stays @vm@'s business. Both are
--     DERIVED from the config, never declared by the program, which is why
--     they are always present. nixos only -- home-manager has no machine to
--     boot and @compile@ never evaluates a home config. There is deliberately no
--     @container@ (systemd-nspawn) rung: running a real init is inherently
--     privileged, so a light rootless \"run the system\" does not exist; nspawn
--     was fragile and bought nothing @vm@ does not (see the run-axis spec).
--     Lightweight witnessing is the artifact rungs' job; a portable OCI image
--     is the future PACKAGE axis (@dockerTools@), not a run rung.
--
-- Clash avoidance: the rung app name (@vm@) is lips-fixed, artifact names are
-- domain-minted, so artifacts live under an @artifact.\<name\>@ namespace while
-- the rung stays top-level. @artifact.vm@ can never equal the rung @vm@ --
-- impossible by construction, no reserved word.
--
-- Nixpkgs is resolved ambiently (the @flake:nixpkgs@ registry indirection), so
-- @compile@ pins nothing, fetches nothing, and emits bit-identical text; the
-- world is resolved at @nix run@ time, the same Heile-Welt softness the old
-- @\<nixpkgs\>@-based VM boot already carried.
module Lips.Nix.Flake
  ( Rungs (..)
  , SiteRung (..)
  , noRungs
  , hasSite
  , hasSiteClaims
  , flakeText
  , runCommands
  ) where

import           Data.Text     (Text)
import qualified Data.Text     as T

import Lips.Nix.Target (Target (..))

-- | The @flake.nix@ text for a compiled directory. @hasArtifacts@ toggles the
-- artifact package output; the target toggles the system rung (nixos gets
-- @apps.vm@ + @packages.vm@; home-manager gets neither, only the module).
-- | What the site axis offers, when it offers anything. A sum rather than two
-- booleans, so "judge the clauses of a program that has none" cannot be written.
data SiteRung = SiteRung
  { srName   :: Text
    -- ^ What the program is installed as. The SAME name the realized module
    -- binds, passed in rather than defaulted here: the flake hardcoded @site@
    -- while the module used the program's own name, so @nix run .#site@ built a
    -- derivation the module never installs.
  , srClaims :: Bool  -- ^ whether there are observables over the behaviour
  }
  deriving (Eq, Show)

-- | Which rungs a compiled directory offers. A record rather than positional
-- booleans, because at four nobody can read the call site.
data Rungs = Rungs
  { hasArtifacts :: Bool
  , hasClaims    :: Bool
  , siteRung     :: Maybe SiteRung
  }
  deriving (Eq, Show)

-- | Nothing offered: the shape a configuration-only program starts from.
noRungs :: Rungs
noRungs = Rungs False False Nothing

-- | Is there a program to run? Derived, so it cannot disagree with the rung.
hasSite :: Rungs -> Bool
hasSite = (/= Nothing) . siteRung

-- | Is there anything to judge? Only ever true where there is a site.
hasSiteClaims :: Rungs -> Bool
hasSiteClaims r = maybe False srClaims (siteRung r)

flakeText :: Target -> Rungs -> Text
flakeText target rungs = T.unlines $
  [ "# lips addressable entry. Generated; do not edit. Running is `nix` over this dir."
  , "{"
  , "  description = \"lips-compiled program (nixpkgs resolved ambiently)\";"
  , "  inputs.nixpkgs.url = \"flake:nixpkgs\";"
  ]
  ++ worldInputs target
  ++
  [ "  outputs = { self, nixpkgs" <> worldArgs target <> " }:"
  , "    let"
  , "      systems = [ \"x86_64-linux\" \"aarch64-linux\" ];"
  , "      forSystems = nixpkgs.lib.genAttrs systems;"
  , "      pkgsFor = system: import nixpkgs { inherit system; };"
  ]
  ++ nixosBuildsLet target (hasArtifacts rungs)
  ++ kubenixBuildsLet target
  ++ terranixBuildsLet target
  ++ [ "    in {" ]
  ++ moduleOutput target
  ++ packagesOutput target rungs
  ++ appsOutput target
  ++ devShellsOutput target
  ++ [ "    };"
     , "}"
     ]

-- | The module output, keyed by world so @imports@\/deploy resolve it. Never a
-- clash source: modules live under their own top-level attribute.
moduleOutput :: Target -> [Text]
moduleOutput Nixos       = [ "      nixosModules.default = import ./default.nix;" ]
moduleOutput HomeManager = [ "      homeManagerModules.default = import ./default.nix;" ]
-- kubenix has no module-output convention of its own, so lips names one, and a
-- config that wants to compose this program imports it like any other module.
moduleOutput Kubenix     = [ "      kubenixModules.default = import ./default.nix;" ]
moduleOutput Terranix    = [ "      terranixModules.default = import ./default.nix;" ]

-- | The world's extra flake inputs. kubenix is a module system of its own, so
-- rendering needs it; it is resolved ambiently (unpinned), the same Heile-Welt
-- softness @flake:nixpkgs@ already carries.
worldInputs :: Target -> [Text]
worldInputs Kubenix  = [ "  inputs.kubenix.url = \"github:hall/kubenix\";" ]
worldInputs Terranix = [ "  inputs.terranix.url = \"github:terranix/terranix\";" ]
worldInputs _        = []

-- | The output-function arguments those inputs add.
worldArgs :: Target -> Text
worldArgs Kubenix  = ", kubenix"
worldArgs Terranix = ", terranix"
worldArgs _        = ""

-- | The per-system kubenix evaluation, defined once in the outer @let@ so both
-- the buildable manifest (@packages@) and the printing rung (@apps@) reference
-- the SAME rendered file. Both output spellings are kubenix's OWN options
-- (@resultYAML@, @result@), so lips converts nothing and owns no format code.
kubenixBuildsLet :: Target -> [Text]
kubenixBuildsLet Kubenix =
  [ "      kubenixBuilds = system:"
  , "        let"
  , "          cfg = (kubenix.evalModules.${system} {"
  , "            module = { kubenix, ... }: {"
  , "              imports = [ kubenix.modules.k8s ./default.nix ];"
  , "            };"
  , "          }).config.kubernetes;"
  , "        in { yaml = cfg.resultYAML; json = cfg.result; };"
  ]
kubenixBuildsLet _ = []

-- | The per-system terranix render, defined once in the outer @let@ so the
-- buildable configuration (@packages@) and the printing rung (@apps@) are the
-- SAME file. @pkgs@ is passed explicitly, so the render uses this flake's
-- nixpkgs rather than terranix's own input, and terranix owns the JSON format
-- (@lib.terranixConfiguration@ produces config.tf.json); lips converts nothing.
terranixBuildsLet :: Target -> [Text]
terranixBuildsLet Terranix =
  [ "      terranixBuilds = system: {"
  , "        config = terranix.lib.terranixConfiguration {"
  , "          pkgs = pkgsFor system;"
  , "          modules = [ ./default.nix ];"
  , "        };"
  , "      };"
  ]
terranixBuildsLet _ = []

-- | The per-system system-rung derivations (nixos only), defined once in the
-- outer @let@ so both @packages@ (build, don't activate) and @apps@ (build +
-- boot) reference the SAME vm\/toplevel. This is the @nix build \<x\>@ vs
-- @nix run \<x\>@ duality: a rung is one derivation reachable two ways, never
-- two definitions. home-manager has no machine, so it emits nothing here.
nixosBuildsLet :: Target -> Bool -> [Text]
nixosBuildsLet HomeManager _ = []
nixosBuildsLet Kubenix _     = []
nixosBuildsLet Terranix _    = []
nixosBuildsLet Nixos hasArtifacts =
  [ "      nixosBuilds = system:"
  , "        let"
  , "          evalNixos = extra: mods: import (nixpkgs + \"/nixos/lib/eval-config.nix\") {"
  , "            inherit system;"
  , "            modules = extra ++ mods;"
  , "          };"
  , "          evalConfig = extra: evalNixos extra [ ./default.nix ];"
    -- Both shell evals carry the same stub, so the subtraction stays symmetric
    -- and neither warns about an unset stateVersion.
  , "          shellStub = { system.stateVersion = \"24.11\"; };"
  , "          # A fixed hostname so the VM boot script has a fixed name to run."
  , "          vm = (evalConfig ["
  , "            (nixpkgs + \"/nixos/modules/virtualisation/qemu-vm.nix\")"
  , "            { system.stateVersion = \"24.11\"; networking.hostName = \"lips\";"
  , "              virtualisation.graphics = false; users.users.root.password = \"\"; }"
  , "          ]).config.system.build.vm;"
    -- The shell rung off the same evaluation: what the config puts on the
    -- system PATH is exactly what a shell for this program should hold. Only
    -- environment.systemPackages is forced, so no VM/bootloader option has to
    -- be satisfied.
    -- The shell rung off the same evaluation. A bare NixOS eval already carries
    -- the whole base system (systemd, grub, coreutils, ...) in
    -- environment.systemPackages, so subtract an empty config's list: what
    -- remains is exactly what THIS program adds to the system PATH.
  , "          basePackages = (evalNixos [ shellStub ] []).config.environment.systemPackages;"
  , "          cfg = (evalConfig [ shellStub ]).config;"
  , "          shellPackages = nixpkgs.lib.subtractLists basePackages"
  , "            cfg.environment.systemPackages" <> shellArtifacts <> ";"
  , "          shell = (pkgsFor system).mkShell { packages = shellPackages; };"
    -- The same subtraction, one option over: the units a BARE eval already
    -- carries are NixOS's own, so what remains is what this program adds. Each
    -- gets the tools shell plus that unit's environment, which is the env the
    -- artifact rungs cannot have (they run with no init). Derived here, so no
    -- unit name is ever known to lips. The name is `service-<unit>`, flat: a
    -- nested set is not a flake leaf, so `nix flake show` would refuse to list
    -- the units it holds (the flat fallback this spec already names for
    -- artifacts). Prefixing is injective and never produces `default`, so a
    -- minted unit name cannot collide with the tools shell.
    -- `env` is mkDerivation's dedicated channel for environment variables, so a
    -- unit variable named `packages` cannot shadow a derivation argument.
  , "          baseServices = builtins.attrNames (evalNixos [ shellStub ] []).config.systemd.services;"
  , "          serviceShells = nixpkgs.lib.listToAttrs (map (u: {"
  , "            name = \"service-${u}\";"
  , "            value = (pkgsFor system).mkShell {"
  , "              packages = shellPackages;"
  , "              env = cfg.systemd.services.${u}.environment;"
  , "            };"
  , "          }) (nixpkgs.lib.subtractLists baseServices (builtins.attrNames cfg.systemd.services)));"
  , "        in { inherit vm shell serviceShells; };"
  ]
  where
    shellArtifacts
      | hasArtifacts = " ++ builtins.attrValues (import ./artifact.nix { pkgs = pkgsFor system; })"
      | otherwise    = ""

-- | @packages@: the buildable things (@nix build \<x\>@ produces, does not
-- activate). Artifacts sit under the @artifact.\<name\>@ namespace (so a
-- domain artifact named @vm@ never clashes with the @vm@ rung); the system
-- rung exposes @vm@ (the boot-script derivation -- building it needs no KVM, so
-- @nix build \<x\>#vm@ is the cheap \"does the whole system build\" check).
packagesOutput :: Target -> Rungs -> [Text]
packagesOutput target rungs
  | null body = []
  | otherwise = [ "      packages = forSystems (system: {" ] ++ body ++ [ "      });" ]
  where
    body = artLine ++ siteLine ++ siteClaimLine ++ claimLine ++ sysLines
    -- The program's own behaviour, built by the runtime its contracts chose. The
    -- builder is the runtime's file, copied verbatim; this flake knows only its
    -- interface.
    siteLine = case siteRung rungs of
      Nothing -> []
      Just sr -> [ "        site = import ./site/build.nix {"
                 , "          pkgs = pkgsFor system; name = " <> srName sr <> "; src = ./site;"
                 , "        };" ]
    -- Judging the clauses is a BUILD that runs them: no machine, no compiled
    -- binary, just the core evaluated with list-backed adapters. A failed claim
    -- exits nonzero, so the build fails and an unheld claim can never read as
    -- held.
    --
    -- The @| tee@ reads like the classic bug where a pipe hides the exit status
    -- of the command before it, and is not one: nixpkgs' stdenv sets
    -- @set -o pipefail@, so the failing claim run still fails the build. Verified
    -- rather than assumed, because the whole rung is worthless if it does not.
    siteClaimLine
      | hasSiteClaims rungs =
          [ "        site-claims = let p = pkgsFor system; in p.runCommand \"site-claims\" {} ''"
          , "          ${import ./site/build.nix {"
          , "            pkgs = p; name = \"site-claims\"; src = ./site; main = \"claims.scm\";"
          , "          }}/bin/site-claims | tee $out"
          , "        '';" ]
      | otherwise = []
    artLine
      | hasArtifacts rungs = [ "        artifact = import ./artifact.nix { pkgs = pkgsFor system; };" ]
      | otherwise    = []
    -- ONE aggregate, so `nix build <dir>#claims` runs EVERY experiment: a claim
    -- that is not built is a claim that did not run, and "not verified" must
    -- never render as verified. World-neutral, because a sandbox claim needs no
    -- machine (only a machine claim does, and those exist in the NixOS world).
    claimLine
      | hasClaims rungs = [ "        claims = (pkgsFor system).linkFarmFromDrvs \"claims\""
                    , "          (builtins.attrValues (import ./claims.nix { pkgs = pkgsFor system; }));" ]
      | otherwise = []
    sysLines = case target of
      -- vm is buildable (no KVM) as the cheap "does the whole system build"
      -- check; booting it (the app) needs KVM.
      Nixos       -> [ "        vm = (nixosBuilds system).vm;" ]
      HomeManager -> []
      -- Building the manifest IS the check that the program renders: kubenix
      -- refuses an unknown field, and a wrong-typed one, at evaluation.
      Kubenix     -> [ "        manifest = (kubenixBuilds system).yaml;"
                     , "        manifest-json = (kubenixBuilds system).json;" ]
      -- Building the configuration IS the check that the program renders: the
      -- module must evaluate and its values must be JSON-representable. Unlike
      -- kubenix, terranix does NOT reject an unknown field (its namespaces are
      -- free-form), so this rung checks rendering only, never field validity.
      Terranix    -> [ "        config = (terranixBuilds system).config;" ]

-- | @apps@ (@nix run \<x\>@ builds + activates), nixos only. Each references
-- the shared 'nixosBuildsLet' derivations, so run and build agree.
appsOutput :: Target -> [Text]
appsOutput HomeManager = []
appsOutput Nixos =
  [ "      apps = forSystems (system:"
  , "        let b = nixosBuilds system; in {"
  , "          vm = { type = \"app\"; program = \"${b.vm}/bin/run-lips-vm\"; };"
  , "        });"
  ]
-- The manifest rungs PRINT: a rendered file is not executable, so the app is a
-- script that cats it, which is what makes @nix run … > manifests.yaml@ (and a
-- pipe into kubectl) the way to write manifests out.
appsOutput Terranix =
  [ "      apps = forSystems (system:"
  , "        let b = terranixBuilds system; p = pkgsFor system; in {"
  , "          config = { type = \"app\"; program = \"${p.writeShellScript \"print-config\" \"cat ${b.config}\"}\"; };"
  , "        });"
  ]
appsOutput Kubenix =
  [ "      apps = forSystems (system:"
  , "        let b = kubenixBuilds system; p = pkgsFor system; in {"
  , "          manifest = { type = \"app\"; program = \"${p.writeShellScript \"print-manifest\" \"cat ${b.yaml}\"}\"; };"
  , "          manifest-json = { type = \"app\"; program = \"${p.writeShellScript \"print-manifest-json\" \"cat ${b.json}\"}\"; };"
  , "        });"
  ]

-- | @devShells@ (@nix develop \<x\>@ enters), nixos only. @default@ so the
-- command needs no attribute: @nix develop path:\<dir\>@.
devShellsOutput :: Target -> [Text]
devShellsOutput HomeManager = []
-- The shell a human needs here holds the client that consumes the rendered
-- configuration. opentofu, not terraform: the same rendered JSON, under a
-- licence nixpkgs ships unencumbered.
devShellsOutput Terranix =
  [ "      devShells = forSystems (system:"
  , "        let p = pkgsFor system; in {"
  , "          default = p.mkShell { packages = [ p.opentofu ]; };"
  , "        });"
  ]
-- The shell a human needs here holds the client that consumes the manifests.
devShellsOutput Kubenix =
  [ "      devShells = forSystems (system:"
  , "        let p = pkgsFor system; in {"
  , "          default = p.mkShell { packages = [ p.kubectl ]; };"
  , "        });"
  ]
devShellsOutput Nixos =
  [ "      devShells = forSystems (system:"
  , "        let b = nixosBuilds system; in {"
  , "          default = b.shell;"
  , "        } // b.serviceShells);"
  ]

-- | The exact commands to print after a successful compile, so the human sees
-- only rungs the program's shape supports (deduce-or-fail: no impossible
-- command is ever shown). @dir@ is the output directory; commands use
-- @path:\<dir\>@ because the compiled dir is derived and gitignored, and
-- @path:@ copies it verbatim, bypassing flake's git rules.
runCommands :: Target -> [Text] -> Rungs -> FilePath -> [Text]
runCommands target artNames rungs dir =
  concatMap artifactLines artNames ++ siteLines ++ systemLines target ++ claimLines
  where
    -- Printed first when the program states behaviour: it is the program itself,
    -- and everything else on the list is scaffolding around it.
    siteLines
      | hasSite rungs =
          [ cmd "run it" "run" (ref "site") "   (the program's own behaviour)"
          , cmd "build it" "build" (ref "site") "" ]
            <> [ cmd "judge it" "build" (ref "site-claims")
                     "   (runs every claim over its clauses)"
               | hasSiteClaims rungs ]
      | otherwise = []
    -- Printed last, and only when the program states observables: it is the rung
    -- that answers "does it do what I said", which is worth reaching for after
    -- the ones that merely build.
    claimLines
      | hasClaims rungs = [ cmd "check what it does" "build" (ref "claims") "   (runs every claim the program states)" ]
      | otherwise = []
    ref suffix = "path:" <> T.pack dir <> "#" <> suffix
    -- One column for the label, one for the verb, so the flake refs line up
    -- however long a verb or an artifact name is.
    cmd label verb target' note =
      "  " <> T.justifyLeft 23 ' ' (label <> ":") <> " "
        <> T.justifyLeft 12 ' ' ("nix " <> verb) <> target' <> note
    artifactLines n =
      [ cmd ("run the " <> n <> " binary") "run"   (ref ("artifact." <> n)) ""
      , cmd "build it"                     "build" (ref ("artifact." <> n)) ""
      , cmd "a shell with it"              "shell" (ref ("artifact." <> n)) ""
      ]
    systemLines Nixos =
      [ cmd "run in a VM"      "run"     (ref "vm") "   (full system, all services; needs KVM)"
      , cmd "build the system" "build"   (ref "vm") "   (checks it builds; no KVM)"
      -- The shell rung needs no attribute: it is devShells.default.
      , cmd "a shell of its tools" "develop" ("path:" <> T.pack dir) "   (what the config puts on PATH)"
      -- The unit name is minted, so lips cannot name it here; the placeholder
      -- plus the stock command that lists the units keeps the hint honest.
      , cmd "...with a unit's env" "develop" (ref "service-<unit>")
          "   (nix flake show " <> "path:" <> T.pack dir <> " lists them)"
      ]
    -- home-manager has no machine to boot: a module is imported into a home
    -- config, not run standalone. Name that instead of a build that can't work.
    systemLines HomeManager =
      [ "  import into your home config: imports = [ " <> T.pack dir <> " ];"
      ]
    -- Rendering is what this world DOES, so the first rung writes the
    -- manifests; the build rung is the same derivation, reached the other way,
    -- and it is the cheap "does it render and validate" check.
    systemLines Kubenix =
      [ cmd "write the manifests" "run"     (ref "manifest")      "   > manifests.yaml"
      , cmd "check it renders"    "build"   (ref "manifest")      ""
      , cmd "the JSON form"       "run"     (ref "manifest-json") "   > manifests.json"
      , cmd "a shell with kubectl" "develop" ("path:" <> T.pack dir) ""
      ]
    -- Same shape as kubenix: rendering is what this world does, so the first
    -- rung writes the file terraform/opentofu consumes, and the build rung is
    -- that same derivation reached the other way.
    systemLines Terranix =
      [ cmd "write the config" "run"     (ref "config") "   > config.tf.json"
      , cmd "check it renders" "build"   (ref "config") ""
      , cmd "a shell with opentofu" "develop" ("path:" <> T.pack dir) ""
      ]
