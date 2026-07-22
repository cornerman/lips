# Options-Schema Grounding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `generate` reject a minted engine whose rules name a NixOS option that does not exist, or fill an option with a value of the wrong type, checked deterministically and offline against the pinned nixpkgs option schema.

**Architecture:** A domain-blind generic layer in the kernel (`Lips.Kernel.OptionType`: a typed `OptionSchema = Map [Text] OptionType` plus a pure checker over minted rules) consumes a schema; a NixOS-specific shell layer outside the kernel (`Lips.Nix.Options`) parses the NixOS `optionsJSON` and its human-readable type strings into that generic schema. `generate` loads the flake-pinned `options.json`, runs the checker as part of its acceptance predicate, and fails loud (deduce-or-fail) naming the offending rule. The kernel learns nothing NixOS-specific; all NixOS knowledge (the shape of `optionsJSON`, the wording of its type descriptions) lives in `Lips.Nix.Options`, exactly as terranix would get its own `Lips.Terraform.Options` later.

**Tech Stack:** Haskell (GHC, `-Wall` clean), `aeson` (already in the dev shell, flake line 13), `hspec` + `QuickCheck`, Nix flakes, `just`.

## Global Constraints

- The kernel is domain-blind: no NixOS-specific string, option name, or type wording may appear in any `Lips.Kernel.*` module. NixOS specifics live only in `Lips.Nix.*` and the flake. (`AGENTS.md`, "The Kernel Knows Nothing".)
- Deduce-or-fail: a missing or mistyped option fails loud, naming the rule and the remedy; never a silent skip and never a guess. (`AGENTS.md` invariant 2.)
- Illegal states unrepresentable; completeness by construction: the type mapping is a closed classifier the engine fills, with an explicit unconstrained fallback, never an open list the kernel enumerates. (invariant 3.)
- The suite and app stay `-Wall` clean.
- Nix flakes see only git-tracked files: `git add` before `nix build`/`nix run`.
- Small single-line commits; rebase + ff-merge to main (no merge commits). Work stays on branch `feat/options-schema` in `.worktrees/options-schema`.
- Fast test loop, run from `kernel/`: `ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`. Or `just test` from the repo root.
- This plan targets committed `HEAD` (7a52116). It modifies `kernel/app/Main.hs`; if the working tree has uncommitted `Main.hs` edits elsewhere, reconcile before starting.

## File Structure

- Create `kernel/src/Lips/Kernel/OptionType.hs` — generic, domain-blind: `OptionType`, `OptionSchema`, `OptionError`, `valueMatches`, `checkEmits`, `renderOptionError`. Pure. No NixOS strings.
- Create `kernel/src/Lips/Nix/Options.hs` — NixOS-specific: `classifyNixType :: Text -> OptionType` (the closed type-string classifier) and `parseNixOptionsJson :: ByteString -> Either Text OptionSchema` (aeson over the `optionsJSON` object shape). Pure (takes bytes).
- Create `kernel/test/Lips/Kernel/OptionTypeSpec.hs` and `kernel/test/Lips/Nix/OptionsSpec.hs` — hspec.
- Create `kernel/test/fixtures/options-mini.json` — a tiny `optionsJSON` fixture.
- Modify `kernel/test/Spec.hs` — register the two new specs.
- Modify `kernel/app/Main.hs` — in the `generate` path, load `$LIPS_OPTIONS_JSON`, run `checkEmits`, reject on error.
- Modify `flake.nix` — add `packages.nixosOptionsJson` (the pinned NixOS manual `optionsJSON` derivation).
- Modify `justfile` — the `generate` and `check-expect` recipes export `LIPS_OPTIONS_JSON` from that package.
- Modify `kernel/README.md` and `DESIGN.md` (section 13 ledger) — document the new acceptance check.

Dependencies between tasks: Task 2 (`Lips.Nix.Options`) consumes Task 1's types. Task 3 (wiring) consumes Tasks 1 and 2. Task 4 (flake) is independent Nix work but Task 3's tests use a fixture, not the flake output, so Task 4 can land last. Task 5 is docs.

---

### Task 1: Generic Option Schema and Checker (`Lips.Kernel.OptionType`)

**Files:**
- Create: `kernel/src/Lips/Kernel/OptionType.hs`
- Test: `kernel/test/Lips/Kernel/OptionTypeSpec.hs`
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.Engine.Data (MapRule(..), Emit(..))` where `emPath :: [Text]`, `emRhs :: Value`, `mrId :: Text`, `mrEmits :: [Emit]`. `Lips.Kernel.Engine.Value (Value(..), HoleType(..))` with constructors `VStr [Piece] | VList [Value] | VBool Bool | VInt Integer | VFloat Double | VPath Text | VNull | VHole HoleType Text` and `HoleType = HInt | HBool | HFloat | HPath`.
- Produces:
  - `data OptionType = OTBool | OTInt | OTFloat | OTString | OTPath | OTListOf OptionType | OTOther Text deriving (Eq, Show)`
  - `type OptionSchema = Data.Map.Strict.Map [Text] OptionType`
  - `data OptionError = UnknownOption Text [Text] | TypeMismatch Text [Text] OptionType Value deriving (Eq, Show)` (first field is the rule id, second the option path)
  - `valueMatches :: OptionType -> Value -> Bool`
  - `checkEmits :: OptionSchema -> [MapRule] -> [OptionError]`
  - `renderOptionError :: OptionError -> Text`

- [ ] **Step 1: Write the failing test**

Create `kernel/test/Lips/Kernel/OptionTypeSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Lips.Kernel.OptionTypeSpec (spec) where

import qualified Data.Map.Strict as Map
import           Test.Hspec

import Lips.Kernel.Engine.Data  (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Value (HoleType (..), Piece (..), Value (..))
import Lips.Kernel.Decision     (Kind (..))
import Lips.Kernel.OptionType

rule :: Text -> [Text] -> Value -> MapRule
rule rid path rhs =
  MapRule { mrId = rid, mrKind = Fact, mrSubject = ["s"]
          , mrEmits = [Emit { emPath = path, emRhs = rhs }] }

spec :: Spec
spec = do
  describe "valueMatches" $ do
    it "accepts an int hole for an integer option" $
      valueMatches OTInt (VHole HInt "value") `shouldBe` True
    it "rejects a quoted string for an integer option" $
      valueMatches OTInt (VStr [PHole "value"]) `shouldBe` False
    it "accepts a string value for a string option" $
      valueMatches OTString (VStr [PHole "value"]) `shouldBe` True
    it "accepts a bool hole for a boolean option" $
      valueMatches OTBool (VHole HBool "value") `shouldBe` True
    it "checks list element type" $ do
      valueMatches (OTListOf OTString) (VList [VStr [PLit "x"]]) `shouldBe` True
      valueMatches (OTListOf OTInt)    (VList [VStr [PHole "v"]]) `shouldBe` False
    it "accepts anything for an unmodelled type" $
      valueMatches (OTOther "submodule") (VBool True) `shouldBe` True
  describe "checkEmits" $ do
    let schema = Map.fromList
          [ (["services","x","port"], OTInt)
          , (["services","x","host"], OTString) ]
    it "passes when every option exists and types match" $
      checkEmits schema
        [ rule "r1" ["services","x","port"] (VHole HInt "value")
        , rule "r2" ["services","x","host"] (VStr [PHole "value"]) ]
        `shouldBe` []
    it "flags an unknown option" $
      checkEmits schema [ rule "r3" ["services","x","nope"] (VBool True) ]
        `shouldBe` [ UnknownOption "r3" ["services","x","nope"] ]
    it "flags a type mismatch" $
      checkEmits schema [ rule "r4" ["services","x","port"] (VStr [PHole "value"]) ]
        `shouldBe` [ TypeMismatch "r4" ["services","x","port"] OTInt (VStr [PHole "value"]) ]
```

Add `import Data.Text (Text)` at the top (used by the `rule` helper).

- [ ] **Step 2: Register the spec and run it to verify it fails**

In `kernel/test/Spec.hs`, add `import qualified Lips.Kernel.OptionTypeSpec` and call it in `main` following the existing registration style (read the file first to match how sibling specs are wired, e.g. an `hspec $ do ... describe "OptionType" Lips.Kernel.OptionTypeSpec.spec`).

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec`
Expected: FAIL — `Could not find module 'Lips.Kernel.OptionType'`.

- [ ] **Step 3: Write minimal implementation**

Create `kernel/src/Lips/Kernel/OptionType.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | A domain-blind, typed schema of option paths, and a pure check that every
-- minted rule fills a known option with a value of a compatible type. The
-- kernel learns nothing NixOS-specific here: it consumes a schema of typed
-- paths (produced by a shell layer such as 'Lips.Nix.Options'), never the
-- wording of any target's type system. Completeness by construction: 'OTOther'
-- is the explicit unconstrained fallback for a type this layer does not model,
-- so an unforeseen option type never forces a rejection.
module Lips.Kernel.OptionType
  ( OptionType (..)
  , OptionSchema
  , OptionError (..)
  , valueMatches
  , checkEmits
  , renderOptionError
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Engine.Data  (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Value (HoleType (..), Value (..))

-- | The modelled option types. 'OTOther' carries the raw type text for any
-- form this layer does not model (submodules, enums, unions, attrsets); it
-- matches every value, so it never rejects.
data OptionType
  = OTBool | OTInt | OTFloat | OTString | OTPath
  | OTListOf OptionType
  | OTOther Text
  deriving (Eq, Show)

-- | A target's option schema: option path (segments) to its type.
type OptionSchema = Map [Text] OptionType

-- | Why a minted rule's option assignment is inadmissible. The first field is
-- the rule id (for a deduce-or-fail echo), the second the option path.
data OptionError
  = UnknownOption Text [Text]
  | TypeMismatch  Text [Text] OptionType Value
  deriving (Eq, Show)

-- | Is this rhs value shape compatible with the option's declared type?
-- Lenient where Nix coerces (int fills a float; a string fills a path), strict
-- where a mistyped hole is a real mint defect (a quoted string in an int
-- option). 'OTOther' is unconstrained.
valueMatches :: OptionType -> Value -> Bool
valueMatches ot v = case (ot, v) of
  (OTBool,   VBool _)        -> True
  (OTBool,   VHole HBool _)  -> True
  (OTInt,    VInt _)         -> True
  (OTInt,    VHole HInt _)   -> True
  (OTFloat,  VFloat _)       -> True
  (OTFloat,  VInt _)         -> True
  (OTFloat,  VHole HFloat _) -> True
  (OTString, VStr _)         -> True
  (OTPath,   VPath _)        -> True
  (OTPath,   VHole HPath _)  -> True
  (OTPath,   VStr _)         -> True
  (OTListOf t, VList vs)     -> all (valueMatches t) vs
  (OTOther _, _)             -> True
  _                          -> False

-- | Check every emit of every rule against the schema. An option not in the
-- schema is 'UnknownOption'; a present option whose value shape does not match
-- its type is 'TypeMismatch'. Empty result means admissible.
checkEmits :: OptionSchema -> [MapRule] -> [OptionError]
checkEmits schema rules =
  [ err
  | r <- rules, e <- mrEmits r
  , err <- case Map.lookup (emPath e) schema of
             Nothing -> [UnknownOption (mrId r) (emPath e)]
             Just t  -> [TypeMismatch (mrId r) (emPath e) t (emRhs e)
                        | not (valueMatches t (emRhs e))]
  ]

renderOptionError :: OptionError -> Text
renderOptionError (UnknownOption rid p) =
  "rule " <> rid <> ": unknown NixOS option " <> dotted p
renderOptionError (TypeMismatch rid p t _) =
  "rule " <> rid <> ": option " <> dotted p <> " has type " <> T.pack (show t)
    <> " but the rule fills it with an incompatible value"

dotted :: [Text] -> Text
dotted = T.intercalate "."
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: PASS, `-Wall` clean.

- [ ] **Step 5: Commit**

```bash
git add kernel/src/Lips/Kernel/OptionType.hs kernel/test/Lips/Kernel/OptionTypeSpec.hs kernel/test/Spec.hs
git commit -m "kernel: generic option-schema type check over minted rules"
```

---

### Task 2: NixOS optionsJSON Parser (`Lips.Nix.Options`)

**Files:**
- Create: `kernel/src/Lips/Nix/Options.hs`
- Create: `kernel/test/Lips/Nix/OptionsSpec.hs`
- Create: `kernel/test/fixtures/options-mini.json`
- Modify: `kernel/test/Spec.hs`

**Interfaces:**
- Consumes: `Lips.Kernel.OptionType (OptionType(..), OptionSchema)`.
- Produces:
  - `classifyNixType :: Text -> OptionType`
  - `parseNixOptionsJson :: Data.ByteString.Lazy.ByteString -> Either Text OptionSchema`

- [ ] **Step 1: Write the fixture**

Create `kernel/test/fixtures/options-mini.json` (the `optionsJSON` shape: a top-level object keyed by dotted option path, each value an object with a `type` string):

```json
{
  "services.x.enable":  { "type": "boolean", "description": "on/off" },
  "services.x.port":    { "type": "16 bit unsigned integer; between 0 and 65535 (both inclusive)", "description": "port" },
  "services.x.host":    { "type": "string", "description": "host" },
  "services.x.paths":   { "type": "list of string", "description": "paths" },
  "services.x.envFile": { "type": "null or absolute path", "description": "env" },
  "services.x.settings":{ "type": "attribute set of anything", "description": "free" }
}
```

- [ ] **Step 2: Write the failing test**

Create `kernel/test/Lips/Nix/OptionsSpec.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}
module Lips.Nix.OptionsSpec (spec) where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import           Test.Hspec

import Lips.Kernel.OptionType (OptionType (..))
import Lips.Nix.Options

spec :: Spec
spec = do
  describe "classifyNixType" $ do
    it "maps boolean"                 $ classifyNixType "boolean" `shouldBe` OTBool
    it "maps any integer wording"     $ classifyNixType "16 bit unsigned integer; between 0 and 65535 (both inclusive)" `shouldBe` OTInt
    it "maps signed integer"          $ classifyNixType "signed integer" `shouldBe` OTInt
    it "maps floating point number"   $ classifyNixType "floating point number" `shouldBe` OTFloat
    it "maps string"                  $ classifyNixType "string" `shouldBe` OTString
    it "maps non-empty string"        $ classifyNixType "non-empty string" `shouldBe` OTString
    it "maps list of string"          $ classifyNixType "list of string" `shouldBe` OTListOf OTString
    it "keeps a union unmodelled"     $ classifyNixType "null or absolute path" `shouldBe` OTOther "null or absolute path"
    it "keeps an attrset unmodelled"  $ classifyNixType "attribute set of anything" `shouldBe` OTOther "attribute set of anything"
  describe "parseNixOptionsJson" $
    it "parses the fixture to a typed schema" $ do
      bytes <- BL.readFile "test/fixtures/options-mini.json"
      let Right schema = parseNixOptionsJson bytes
      Map.lookup ["services","x","enable"] schema `shouldBe` Just OTBool
      Map.lookup ["services","x","port"]   schema `shouldBe` Just OTInt
      Map.lookup ["services","x","paths"]  schema `shouldBe` Just (OTListOf OTString)
      Map.lookup ["services","x","envFile"] schema `shouldBe` Just (OTOther "null or absolute path")
```

Register it in `kernel/test/Spec.hs` (import `qualified Lips.Nix.OptionsSpec` and call `Lips.Nix.OptionsSpec.spec`). The fixture read uses a relative path, so tests must run from `kernel/` (they already do).

- [ ] **Step 3: Run to verify it fails**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec`
Expected: FAIL — `Could not find module 'Lips.Nix.Options'`.

- [ ] **Step 4: Write minimal implementation**

Create `kernel/src/Lips/Nix/Options.hs`:

```haskell
{-# LANGUAGE OverloadedStrings #-}

-- | The NixOS-specific shell layer: turn a NixOS @optionsJSON@ document into
-- the kernel's domain-blind 'OptionSchema'. All NixOS knowledge lives here --
-- the JSON object shape and the wording of NixOS type descriptions -- so the
-- kernel stays blind. A different target (terranix) would add its own module
-- producing the same 'OptionSchema'.
--
-- The NixOS @type@ field is a human description string, not a structured type
-- (e.g. @\"16 bit unsigned integer; between 0 and 65535 (both inclusive)\"@),
-- so 'classifyNixType' is a closed classifier over the scalar and list
-- wordings; every other wording (unions, enums, submodules, attrsets) maps to
-- 'OTOther', which the checker leaves unconstrained.
module Lips.Nix.Options
  ( classifyNixType
  , parseNixOptionsJson
  ) where

import           Data.Aeson           (Value (..), eitherDecode, (.:))
import           Data.Aeson.Types     (parseEither, withObject)
import qualified Data.Aeson.KeyMap    as KM
import qualified Data.Aeson.Key       as K
import           Data.ByteString.Lazy (ByteString)
import qualified Data.Map.Strict      as Map
import           Data.Text            (Text)
import qualified Data.Text            as T

import Lips.Kernel.OptionType (OptionSchema, OptionType (..))

-- | Classify one NixOS type description. List is tested first (its element
-- text may itself contain a scalar keyword); then scalar keywords; else the
-- raw text is kept as 'OTOther'.
classifyNixType :: Text -> OptionType
classifyNixType raw0
  | Just el <- T.stripPrefix "list of " raw = OTListOf (classifyNixType el)
  | raw == "boolean"                        = OTBool
  | "integer" `T.isInfixOf` raw             = OTInt
  | raw == "floating point number"          = OTFloat
  | isString raw                            = OTString
  | raw == "path" || raw == "absolute path" = OTPath
  | otherwise                               = OTOther raw
  where
    raw = T.strip raw0
    -- Only a bare string family, not a union like "null or string".
    isString r = r == "string" || r == "non-empty string"
              || "string " `T.isPrefixOf` r || "strings " `T.isPrefixOf` r
```

Then the parser. The top level is a JSON object; each value is an object with a `type` string. Build the map from dotted key to classified type:

```haskell
-- | Parse an @optionsJSON@ document to an 'OptionSchema'. Keys are dotted
-- option paths; only the @type@ field of each entry is read.
parseNixOptionsJson :: ByteString -> Either Text OptionSchema
parseNixOptionsJson bytes = do
  top <- either (Left . T.pack) Right (eitherDecode bytes)
  either (Left . T.pack) Right (parseEither toSchema top)
  where
    toSchema = withObject "optionsJSON" $ \km ->
      fmap Map.fromList $
        traverse
          (\(k, val) -> do
              ty <- withObject "option" (.: "type") val
              pure (T.splitOn "." (K.toText k), classifyNixType ty))
          (KM.toList km)
```

Notes for the implementer: `aeson` ≥ 2 provides `Data.Aeson.KeyMap` and `Data.Aeson.Key`; the dev-shell `aeson` is version 2. If GHC reports these modules missing, check the pinned `aeson` major version and use `Data.HashMap.Strict` with `Data.Text` keys for aeson 1. The `.: "type"` yields a `Text`.

- [ ] **Step 5: Run to verify it passes**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: PASS, `-Wall` clean.

- [ ] **Step 6: Commit**

```bash
git add kernel/src/Lips/Nix/Options.hs kernel/test/Lips/Nix/OptionsSpec.hs kernel/test/fixtures/options-mini.json kernel/test/Spec.hs
git commit -m "nix: parse optionsJSON into the generic option schema"
```

---

### Task 3: Enforce the Check in `generate` (deduce-or-fail)

**Files:**
- Modify: `kernel/app/Main.hs` (the `generate` command path)

**Interfaces:**
- Consumes: `Lips.Kernel.OptionType (checkEmits, renderOptionError)`, `Lips.Nix.Options (parseNixOptionsJson)`, `Lips.Generate.Minting (assemble)` and `Lips.Kernel.Lang.Lang (EngineData(edRules))` to reach the minted `[MapRule]`. The env var `LIPS_OPTIONS_JSON` holds the path to `options.json`.
- Produces: no new exported symbol; `generate` gains one acceptance gate.

Read `kernel/app/Main.hs` first to find where the minted engine is assembled and where the existing validation (full run + `nix-instantiate --parse`) accepts or rejects it. The new gate runs alongside those, before writing `.lang`.

- [ ] **Step 1: Write the failing test (an engine with a bogus option is rejected)**

`generate` is IO and model-driven, so test the gate at the pure boundary it wraps: add to `kernel/test/Lips/Kernel/OptionTypeSpec.hs` a check that a realistic minted rule set with one bogus option yields exactly one error. This pins the behavior the IO wiring must surface.

```haskell
    it "flags exactly the bogus option in a mixed rule set" $ do
      let schema = Map.fromList
            [ (["services","restic","backups","x","paths"], OTListOf OTString) ]
          good = rule "r1" ["services","restic","backups","x","paths"]
                      (VList [VStr [PHole "value"]])
          bad  = rule "r2" ["services","restic","backups","x","nonsuch"]
                      (VStr [PHole "value"])
      map renderOptionError (checkEmits schema [good, bad])
        `shouldBe` ["rule r2: unknown NixOS option services.restic.backups.x.nonsuch"]
```

Add `renderOptionError` and `OptionType(..)` to the import list already present.

- [ ] **Step 2: Run to verify it fails**

Run: `cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec`
Expected: FAIL (compile error until the import is present, then assertion runs).

- [ ] **Step 3: Implement the pure part, verify the test passes**

The pure part is already implemented in Task 1; this step only confirms `renderOptionError`'s exact wording matches the test. Run:
`cd kernel && ghc -Wall -isrc -itest test/Spec.hs -outputdir /tmp/lips-build -o /tmp/lips-spec && /tmp/lips-spec`
Expected: PASS.

- [ ] **Step 4: Wire the gate into `generate` in `kernel/app/Main.hs`**

In the `generate` handler, after the candidates are parsed and the engine assembled (the point where `[MapRule]` is available, e.g. `edRules (assemble items)`), and before writing `.lang`, add:

```haskell
    -- Deduce-or-fail: every minted rule must fill a real, correctly typed
    -- NixOS option. The schema is the pinned nixpkgs optionsJSON; its path
    -- arrives via LIPS_OPTIONS_JSON (the justfile wires it from the flake).
    optsPath <- lookupEnv "LIPS_OPTIONS_JSON"
    schema <- case optsPath of
      Nothing -> die "generate: LIPS_OPTIONS_JSON is unset; run via `just generate` \
                     \(it builds the pinned nixpkgs option schema) or export the path to options.json"
      Just p  -> do
        bytes <- BL.readFile p
        case parseNixOptionsJson bytes of
          Left e  -> die (T.unpack ("generate: cannot read option schema at " <> T.pack p <> ": " <> e))
          Right s -> pure s
    case checkEmits schema (edRules (assemble items)) of
      []   -> pure ()
      errs -> die (T.unpack (T.unlines
                    ( "generate: engine rejected -- rules name options that do not exist or are mistyped:"
                    : map (("  - " <>) . renderOptionError) errs
                    ++ ["fix by regenerating; do not hand-edit the engine"] )))
```

Add imports to `Main.hs`: `import System.Environment (lookupEnv)` (if not already), `import System.Exit (die)` (or reuse the module's existing failure helper — match how the current validation reports errors; if it uses a `RunError`-style value rather than `die`, thread the option errors through that same channel instead of `die`), `import qualified Data.ByteString.Lazy as BL`, `import qualified Data.Text as T`, `import Lips.Kernel.OptionType (checkEmits, renderOptionError)`, `import Lips.Nix.Options (parseNixOptionsJson)`, and `import Lips.Kernel.Lang.Lang (EngineData(edRules))` if `assemble`/`edRules` are not already in scope.

Match the surrounding style: if `generate` already funnels rejections through one function that prints and exits non-zero, call that instead of `die` so the echo format stays consistent.

- [ ] **Step 5: Build the binary to verify it compiles**

Run: `cd kernel && ghc -Wall -isrc -iapp app/Main.hs -outputdir /tmp/lips-app -o /tmp/lips-app`
Expected: compiles, `-Wall` clean. (This is a compile check; a full `generate` run needs `pi` and the schema and is exercised in Task 4.)

- [ ] **Step 6: Commit**

```bash
git add kernel/app/Main.hs kernel/test/Lips/Kernel/OptionTypeSpec.hs
git commit -m "generate: reject rules that name unknown or mistyped NixOS options"
```

---

### Task 4: Provide the Pinned Schema (flake + justfile)

**Files:**
- Modify: `flake.nix`
- Modify: `justfile`

**Interfaces:**
- Produces: flake output `packages.<system>.nixosOptionsJson` (a derivation containing `share/doc/nixos/options.json`). The justfile exports `LIPS_OPTIONS_JSON` to that file for `generate` and `check-expect`.

- [ ] **Step 1: Add the schema package to `flake.nix`**

In the `packages = forAll (pkgs: { ... })` attrset, add an entry that builds the NixOS manual `optionsJSON` from the pinned `nixpkgs` input (so the schema matches the nixpkgs the realized module is evaluated against):

```nix
        nixosOptionsJson =
          (import (nixpkgs + "/nixos") {
            inherit (pkgs.stdenv.hostPlatform) system;
            configuration = { };
          }).config.system.build.manual.optionsJSON;
```

- [ ] **Step 2: Verify the package builds and exposes options.json**

Run:
```bash
git add flake.nix
nix build .#nixosOptionsJson --print-out-paths
ls "$(nix build .#nixosOptionsJson --print-out-paths --no-link)"/share/doc/nixos/options.json
```
Expected: a store path, and the `options.json` file exists. (Adjust the attribute path in the incantation if the pinned nixpkgs names the manual build differently; the canonical attribute is `config.system.build.manual.optionsJSON`.)

- [ ] **Step 3: Wire `LIPS_OPTIONS_JSON` into the justfile**

Change the `generate` recipe (and `check-expect`, which runs the same acceptance check per the recipe comment) to export the path before invoking the binary:

```make
generate program model="":
    #!/usr/bin/env bash
    set -euo pipefail
    export LIPS_OPTIONS_JSON="$(nix build .#nixosOptionsJson --no-link --print-out-paths)/share/doc/nixos/options.json"
    if [ -n "{{model}}" ]; then
      nix run . -- generate "{{model}}" "{{program}}"
    else
      nix run . -- generate "{{program}}"
    fi
```

- [ ] **Step 4: End-to-end check on an existing example**

Regenerating needs `pi`; instead verify the gate accepts a known-good committed engine by running the pure check against the real schema. From the repo root:

```bash
export LIPS_OPTIONS_JSON="$(nix build .#nixosOptionsJson --no-link --print-out-paths)/share/doc/nixos/options.json"
# Confirm the schema contains the options the backup example fills:
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); \
  [print(k, k in d) for k in ['services.restic.backups.ledger.paths','services.restic.backups.ledger.repository']]" \
  "$LIPS_OPTIONS_JSON"
```
Expected: both options print `True`. If any committed example's engine names an option now flagged unknown, that is a real finding: record it (it means the example minted a non-existent option) and raise it with the maintainer before "fixing" — do not silence the check.

- [ ] **Step 5: Commit**

```bash
git add flake.nix justfile
git commit -m "flake: pinned nixos option schema; justfile wires LIPS_OPTIONS_JSON"
```

---

### Task 5: Document the New Acceptance Check

**Files:**
- Modify: `kernel/README.md` (the paragraph describing what `generate` validates)
- Modify: `DESIGN.md` (section 13 ledger)

- [ ] **Step 1: Update the kernel README**

In `kernel/README.md`, the sentence "validates it by a full run plus a Nix parse (`nix-instantiate --parse`)" becomes: "validates it by a full run, a Nix parse (`nix-instantiate --parse`), and an **option-schema check** — every minted rule must fill a NixOS option that exists in the pinned nixpkgs and with a value of a compatible type, or the engine is rejected (deduce-or-fail)."

- [ ] **Step 2: Update the milestone ledger**

In section 13 of the design doc, add a "Done" entry: "Option-schema grounding: `generate` checks every minted rule's option path and value type against the pinned nixpkgs `optionsJSON` (`Lips.Nix.Options` → `Lips.Kernel.OptionType`), rejecting unknown or mistyped options offline. Kernel stays domain-blind; NixOS type-string wording lives in `Lips.Nix.Options`."

- [ ] **Step 3: Run the full fast suite once more**

Run: `just test`
Expected: PASS, `-Wall` clean.

- [ ] **Step 4: Commit**

```bash
git add kernel/README.md DESIGN.md
git commit -m "docs: option-schema check in generate acceptance (ledger + README)"
```

---

## Out of Scope (Separate Plans to Follow)

- **Steal #2 — derived tooling from the schema.** Completion, hover, and option search exported from the same `OptionSchema`. A `Lips.Lsp` module already exists, so this plan will extend it to consume `Lips.Nix.Options`. Its own plan; depends on this one's ingestion.
- **Steal #3 — bounded repair loop.** On a rejected mint (including the option errors this plan produces), re-prompt `pi` with the exact diagnostic as context, up to a bound, alongside the existing resampling-unanimity in `Lips.Generate.Harness`. Orthogonal to this plan; its own plan.
- **Prompt-side grounding (assist, not gate).** Feeding the relevant slice of the schema into the mint prompt so the model picks the right hole type up front. Pairs with steal #3; deferred so the deterministic gate lands first and stands alone.

## Self-Review

- **Spec coverage:** option existence check (Tasks 1, 3), type-compatibility check / type-derived holes as rejection of mismatches (Tasks 1, 3), offline + deterministic via pinned nixpkgs (Task 4), deduce-or-fail echo naming the rule (Task 3), kernel stays domain-blind with NixOS specifics isolated (Tasks 1 vs 2). All covered.
- **Placeholder scan:** every code step shows complete code; the two "read the file first" instructions (Spec.hs registration style, Main.hs rejection channel) adapt one line to existing conventions and are not code placeholders.
- **Type consistency:** `emPath :: [Text]`, `emRhs :: Value`, `mrId`, `mrEmits`, `HoleType(HInt|HBool|HFloat|HPath)`, `Value` constructors, `OptionType`/`OptionSchema`/`OptionError`/`checkEmits`/`valueMatches`/`renderOptionError`/`classifyNixType`/`parseNixOptionsJson` are used identically across tasks.
- **Open risk to verify during Task 2:** the pinned `aeson` major version (KeyMap API is aeson ≥ 2). Task 2 Step 4 notes the fallback. During Task 4, confirm the manual `optionsJSON` attribute name against the pinned nixpkgs.
