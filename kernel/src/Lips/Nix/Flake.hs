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

import Lips.World (Rung (..), World (..))

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

flakeText :: World -> Rungs -> Text
flakeText w rungs = T.unlines $
  [ "# lips addressable entry. Generated; do not edit. Running is `nix` over this dir."
  , "{"
  , "  description = \"lips-compiled program (nixpkgs resolved ambiently)\";"
  , "  inputs.nixpkgs.url = \"flake:nixpkgs\";"
  ]
  ++ wInputs w
  ++
  [ "  outputs = { self, nixpkgs" <> wInputArgs w <> " }:"
  , "    let"
  , "      systems = [ \"x86_64-linux\" \"aarch64-linux\" ];"
  , "      forSystems = nixpkgs.lib.genAttrs systems;"
  , "      pkgsFor = system: import nixpkgs { inherit system; };"
  ]
  -- The world's own let-bindings, verbatim. Nothing in this skeleton reads
  -- them: only the world's own packages\/apps\/devShells slots do, so what they
  -- are called is the world file's business.
  ++ wBuilds w
  ++ [ "    in {" ]
  -- Keyed by the world's own attribute name so @imports@\/deploy resolve it.
  -- Never a clash source: modules live under their own top-level attribute.
  ++ [ "      " <> wModuleAttr w <> ".default = import ./default.nix;" ]
  ++ packagesOutput w rungs
  ++ wrapOutput "apps" (wApps w)
  ++ wrapOutput "devShells" (wDevShells w)
  ++ [ "    };"
     , "}"
     ]

-- | @packages@: the buildable things (@nix build \<x\>@ produces, does not
-- activate). The only output lips contributes entries to: artifacts (under the
-- @artifact.\<name\>@ namespace, so a domain artifact named @vm@ never clashes
-- with a world rung called @vm@), the program's own site, and the claims
-- aggregate. The world's entries follow, so a world adds rungs without lips
-- knowing what they are.
packagesOutput :: World -> Rungs -> [Text]
packagesOutput w rungs
  | null body = []
  | otherwise = [ "      packages = forSystems (system: {" ] ++ body ++ [ "      });" ]
  where
    body = artLine ++ siteLine ++ siteClaimLine ++ claimLine ++ worldLines
    worldLines = maybe [] textLines (wPackages w)
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

-- | Wrap one world slot as a per-system output: the slot is the body of
-- @forSystems (system: \<body\>)@, so a world writes an attrset, a @let@, or a
-- @\/\/@ merge (nixos\'s per-unit shells are exactly that) without lips knowing
-- which. The closing paren joins the last line, so the generated Nix reads as a
-- human would write it.
wrapOutput :: Text -> Maybe Text -> [Text]
wrapOutput _ Nothing = []
wrapOutput name (Just body) = case textLines body of
  []  -> []
  ls  -> [ "      " <> name <> " = forSystems (system:" ]
           ++ init ls ++ [ last ls <> ");" ]

-- | A slot's lines, without the trailing blank @unlines@ leaves behind. Only
-- trailing ones: a blank line inside a slot is the world's own formatting.
textLines :: Text -> [Text]
textLines = reverse . dropWhile (T.null . T.strip) . reverse . T.lines

-- | The exact commands to print after a successful compile, so the human sees
-- only rungs the program's shape supports (deduce-or-fail: no impossible
-- command is ever shown). @dir@ is the output directory; commands use
-- @path:\<dir\>@ because the compiled dir is derived and gitignored, and
-- @path:@ copies it verbatim, bypassing flake's git rules.
runCommands :: World -> [Text] -> Rungs -> FilePath -> [Text]
runCommands w artNames rungs dir =
  concatMap artifactLines artNames ++ siteLines ++ map worldRung (wRungs w) ++ claimLines
  where
    -- Printed first when the program states behaviour: it is the program itself,
    -- and everything else on the list is scaffolding around it.
    siteLines
      | hasSite rungs =
          [ cmd "run it" "run" (ref "site") "(the program's own behaviour)"
          , cmd "build it" "build" (ref "site") "" ]
            <> [ cmd "judge it" "build" (ref "site-claims")
                     "(runs every claim over its clauses)"
               | hasSiteClaims rungs ]
      | otherwise = []
    -- Printed last, and only when the program states observables: it is the rung
    -- that answers "does it do what I said", which is worth reaching for after
    -- the ones that merely build.
    claimLines
      | hasClaims rungs = [ cmd "check what it does" "build" (ref "claims") "(runs every claim the program states)" ]
      | otherwise = []
    -- The world's own rungs, as the world file spells them. An empty attribute
    -- means the bare directory (a devShells.default needs no attribute); a
    -- literal line is a world with nothing to run, which says what to do
    -- instead. @<dir>@ is the world's hole for the output directory.
    worldRung (RungLine t) = "  " <> fill t
    worldRung (RungCmd label verb attr note)
      | T.null attr = cmd label verb ("path:" <> T.pack dir) (fill note)
      | otherwise   = cmd label verb (ref (fill attr)) (fill note)
    fill = T.replace "<dir>" (T.pack dir)
    ref suffix = "path:" <> T.pack dir <> "#" <> suffix
    -- One column for the label, one for the verb, so the flake refs line up
    -- however long a verb or an artifact name is. A note is set off by a fixed
    -- gap, so a world file writes the note itself and never its spacing.
    cmd label verb target' note =
      "  " <> T.justifyLeft 23 ' ' (label <> ":") <> " "
        <> T.justifyLeft 12 ' ' ("nix " <> verb) <> target'
        <> (if T.null note then "" else "   " <> note)
    artifactLines n =
      [ cmd ("run the " <> n <> " binary") "run"   (ref ("artifact." <> n)) ""
      , cmd "build it"                     "build" (ref ("artifact." <> n)) ""
      , cmd "a shell with it"              "shell" (ref ("artifact." <> n)) ""
      ]
