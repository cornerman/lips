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
--   * system rungs (@container@, @vm@): evaluate @.\/default.nix@ through the
--     NixOS module system and boot the result. @container@ (systemd-nspawn) is
--     the complete NixOS userspace sharing the host kernel; @vm@ (QEMU) adds
--     the kernel\/boot\/hardware layer. nixos only -- home-manager has no
--     machine to boot.
--
-- Clash avoidance: rung app names (@vm@, @container@) are lips-fixed, artifact
-- names are domain-minted, so artifacts live under an @artifact.\<name\>@
-- namespace while rungs stay top-level. @artifact.vm@ can never equal the rung
-- @vm@ -- impossible by construction, no reserved word.
--
-- Nixpkgs is resolved ambiently (the @flake:nixpkgs@ registry indirection), so
-- @compile@ pins nothing, fetches nothing, and emits bit-identical text; the
-- world is resolved at @nix run@ time, the same Heile-Welt softness the old
-- @\<nixpkgs\>@-based VM boot already carried.
module Lips.Nix.Flake
  ( flakeText
  , runCommands
  ) where

import           Data.Text     (Text)
import qualified Data.Text     as T

import Lips.Nix.Target (Target (..))

-- | The @flake.nix@ text for a compiled directory. @hasArtifacts@ toggles the
-- artifact package output; the target toggles the system rungs (nixos gets
-- @apps.vm@\/@apps.container@; home-manager gets neither, only the module).
flakeText :: Target -> Bool -> Text
flakeText target hasArtifacts = T.unlines $
  [ "# lips addressable entry. Generated; do not edit. Running is `nix` over this dir."
  , "{"
  , "  description = \"lips-compiled program (nixpkgs resolved ambiently)\";"
  , "  inputs.nixpkgs.url = \"flake:nixpkgs\";"
  , "  outputs = { self, nixpkgs }:"
  , "    let"
  , "      systems = [ \"x86_64-linux\" \"aarch64-linux\" ];"
  , "      forSystems = nixpkgs.lib.genAttrs systems;"
  , "      pkgsFor = system: import nixpkgs { inherit system; };"
  ]
  ++ nixosBuildsLet target
  ++ [ "    in {" ]
  ++ moduleOutput target
  ++ packagesOutput target hasArtifacts
  ++ appsOutput target
  ++ [ "    };"
     , "}"
     ]

-- | The module output, keyed by world so @imports@\/deploy resolve it. Never a
-- clash source: modules live under their own top-level attribute.
moduleOutput :: Target -> [Text]
moduleOutput Nixos       = [ "      nixosModules.default = import ./default.nix;" ]
moduleOutput HomeManager = [ "      homeManagerModules.default = import ./default.nix;" ]

-- | The per-system system-rung derivations (nixos only), defined once in the
-- outer @let@ so both @packages@ (build, don't activate) and @apps@ (build +
-- boot) reference the SAME vm\/toplevel. This is the @nix build \<x\>@ vs
-- @nix run \<x\>@ duality: a rung is one derivation reachable two ways, never
-- two definitions. home-manager has no machine, so it emits nothing here.
nixosBuildsLet :: Target -> [Text]
nixosBuildsLet HomeManager = []
nixosBuildsLet Nixos =
  [ "      nixosBuilds = system:"
  , "        let"
  , "          pkgs = pkgsFor system;"
  , "          evalConfig = extra: import (nixpkgs + \"/nixos/lib/eval-config.nix\") {"
  , "            inherit system;"
  , "            modules = extra ++ [ ./default.nix ];"
  , "          };"
  , "          # A fixed hostname so the VM boot script has a fixed name to run."
  , "          vm = (evalConfig ["
  , "            (nixpkgs + \"/nixos/modules/virtualisation/qemu-vm.nix\")"
  , "            { system.stateVersion = \"24.11\"; networking.hostName = \"lips\";"
  , "              virtualisation.graphics = false; users.users.root.password = \"\"; }"
  , "          ]).config.system.build.vm;"
  , "          # container: the complete NixOS userspace (all services), booted"
  , "          # under systemd-nspawn sharing the host kernel. Needs root; the"
  , "          # kernel/boot/hardware layer is the vm rung's job, not this one."
  , "          toplevel = (evalConfig ["
  , "            { system.stateVersion = \"24.11\"; networking.hostName = \"lips\"; boot.isContainer = true; }"
  , "          ]).config.system.build.toplevel;"
  , "          runContainer = pkgs.writeShellScript \"run-lips-container\" ''"
  , "            root=$(${pkgs.coreutils}/bin/mktemp -d)"
  , "            trap '${pkgs.coreutils}/bin/rm -rf \"$root\"' EXIT"
  , "            ${pkgs.coreutils}/bin/mkdir -p \"$root/etc\" \"$root/sbin\""
  , "            # nspawn needs an os-release and its own init to boot and register."
  , "            : > \"$root/etc/os-release\""
  , "            ${pkgs.coreutils}/bin/ln -sf ${toplevel}/init \"$root/sbin/init\""
  , "            # --register=no --keep-unit: don't require machined/nsresourced."
  , "            exec ${pkgs.systemd}/bin/systemd-nspawn --quiet --boot \\"
  , "              --register=no --keep-unit \\"
  , "              --directory=\"$root\" --bind-ro=/nix/store \"$@\""
  , "          '';"
  , "        in { inherit vm toplevel runContainer; };"
  ]

-- | @packages@: the buildable things (@nix build \<x\>@ produces, does not
-- activate). Artifacts sit under the @artifact.\<name\>@ namespace (so a
-- domain artifact named @vm@ never clashes with the @vm@ rung); the system
-- rungs expose @vm@ (the boot script derivation) and @container@ (the whole
-- system @toplevel@ -- a cheap \"does it build\" check, no KVM\/root).
packagesOutput :: Target -> Bool -> [Text]
packagesOutput target hasArtifacts
  | null body = []
  | otherwise = [ "      packages = forSystems (system: {" ] ++ body ++ [ "      });" ]
  where
    body = artLine ++ sysLines
    artLine
      | hasArtifacts = [ "        artifact = import ./artifact.nix { pkgs = pkgsFor system; };" ]
      | otherwise    = []
    sysLines = case target of
      Nixos       -> [ "        vm = (nixosBuilds system).vm;"
                     , "        container = (nixosBuilds system).toplevel;" ]
      HomeManager -> []

-- | @apps@ (@nix run \<x\>@ builds + activates), nixos only. Each references
-- the shared 'nixosBuildsLet' derivations, so run and build agree.
appsOutput :: Target -> [Text]
appsOutput HomeManager = []
appsOutput Nixos =
  [ "      apps = forSystems (system:"
  , "        let b = nixosBuilds system; in {"
  , "          vm = { type = \"app\"; program = \"${b.vm}/bin/run-lips-vm\"; };"
  , "          container = { type = \"app\"; program = \"${b.runContainer}\"; };"
  , "        });"
  ]

-- | The exact commands to print after a successful compile, so the human sees
-- only rungs the program's shape supports (deduce-or-fail: no impossible
-- command is ever shown). @dir@ is the output directory; commands use
-- @path:\<dir\>@ because the compiled dir is derived and gitignored, and
-- @path:@ copies it verbatim, bypassing flake's git rules.
runCommands :: Target -> [Text] -> FilePath -> [Text]
runCommands target artNames dir =
  concatMap artifactLines artNames ++ systemLines target
  where
    ref suffix = "path:" <> T.pack dir <> "#" <> suffix
    artifactLines n =
      [ "  run the " <> n <> " binary:   nix run   " <> ref ("artifact." <> n)
      , "  build it:              nix build " <> ref ("artifact." <> n)
      , "  a shell with it:       nix shell " <> ref ("artifact." <> n)
      ]
    systemLines Nixos =
      [ "  run in a container:    nix run   " <> ref "container" <> "   (all services; needs root, no KVM)"
      , "  run in a VM:           nix run   " <> ref "vm" <> "   (adds kernel/boot; needs KVM)"
      , "  build the system only: nix build " <> ref "container"
      ]
    -- home-manager has no machine to boot: a module is imported into a home
    -- config, not run standalone. Name that instead of a build that can't work.
    systemLines HomeManager =
      [ "  import into your home config: imports = [ " <> T.pack dir <> " ];"
      ]
