{-# LANGUAGE OverloadedStrings #-}

-- | Where a world's option schema comes from, and what a name means in it.
--
-- One resolution per run: 'ensureOptionSchema' locks the flakeref (or takes the
-- caller's document), builds the option JSON with nix, and hands back BOTH the
-- path and the pin recorded in @.generation@ -- so the schema a mint is ground
-- against and the schema the gate judges against cannot be two different things
-- (invariant 6: no input steers a generation unrecorded).
--
-- Everything here shells out to nix and is therefore the imperative shell
-- around a pure core: 'Lips.Kernel.OptionType' answers what a name means,
-- 'Lips.Nix.Schema' parses the document, and this module only decides which
-- document that is. @check@ never reaches any of it, which is what keeps a
-- committed engine judgeable offline.
module Lips.Schema
  ( optionsQuery
  , renderAnswer
  , assertOptionsAdmissible
  , ensureOptionSchema
  , lockFlakeRef
  ) where

import           Control.Exception  (IOException, try)
import           Data.Aeson         (Value (..), decode)
import qualified Data.Aeson.KeyMap  as KM
import qualified Data.ByteString    as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import           Data.Text          (Text)
import qualified Data.Text          as T
import           System.Environment (lookupEnv)
import           System.Exit        (ExitCode (..))
import           System.Process     (readProcessWithExitCode)

import           Lips.Cli.Output               (die, note, report, sayAnswer, setState, step, tshow)
import           Lips.Generate.Record          (hashBytes)
import           Lips.Kernel.Lang.Store        (EngineData (..))
import           Lips.Kernel.OptionType        (Answer (..), answerQuery, checkEmits, dotted,
                                                renderOptionError, renderOptionType)
import           Lips.Nix.Schema               (schemaFor)
import           Lips.Nix.Target               (Target (..), targetSlug)
import           Lips.Report                   (plural, validationReport)

-- | @options@: look a query up in the target world's pinned option schema and
-- print the answer. This verb is both a human's lookup and the target of the
-- mint's lookup tool (@query_options@), so what a human reads here is exactly what
-- the model is told -- there is no second, model-facing renderer to drift.
--
-- It never calls a model (invariant 1 holds trivially: no model runs anywhere
-- but generate) and it never writes anything.
optionsQuery :: Target -> Maybe String -> Int -> Text -> IO ()
optionsQuery target mschema limit query = do
  -- The pin is discarded here: a lookup records nothing. Only generate, which
  -- commits an engine, has a record to name it in.
  (schemaPath, _) <- ensureOptionSchema target mschema ("options " <> query)
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  bytes <- case mbytes of
    Left e -> die (report
      ("lips can't read the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run it again.")
    Right b -> pure b
  case schemaFor target bytes of
    Left why -> die (report
      ("lips can't parse the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [why]
      "→ run it again.")
    -- Exit 0 even for Nowhere: "no option matches that" is a valid answer to a
    -- question, not a failure of the command.
    Right schema -> sayAnswer (renderAnswer query (answerQuery limit query schema))

-- | Render a lookup for a reader who must decide what to ask NEXT, which is why
-- a namespace answer says how to drill in and a miss suggests how to re-word.
renderAnswer :: Text -> Answer -> Text
renderAnswer query ans = case ans of
  Leaves ls -> T.unlines
    [ dotted p <> " : " <> renderOptionType t | (p, t) <- ls ]
  Namespaces ns hidden -> T.unlines $
    [ dotted p <> " (" <> plural n "option" <> ")" | (p, n) <- ns ]
      ++ [ "… and " <> plural hidden "more namespace" <> "." | hidden > 0 ]
      ++ [ "Ask again with one of these paths to see its options." ]
  -- The honest answer for a free-form region: the path is admissible (the same
  -- schema's gate accepts it), and the schema knows nothing about it. Saying
  -- "no option matches" here would call a legal path a typo; saying only "fine"
  -- would sell an unchecked name as confirmed.
  Freeform anc t -> T.unlines
    [ query <> " is below " <> dotted anc <> " : " <> renderOptionType t
    , "That option is free-form: every path under it is accepted, and none of"
    , "them is checked -- this schema cannot confirm the name " <> query <> "."
    , "Emit it only from documentation you actually have; otherwise refuse."
    ]
  Nowhere -> T.unlines
    [ "no option matches " <> query
    , "Try a shorter query, or a different word for the same thing."
    ]

-- | Deduce-or-fail: every minted rule must fill a real, correctly typed NixOS
-- option. The schema document is located ONCE per run by 'ensureOptionSchema'
-- and handed in, so the schema this gate judges against is the very one the
-- record names -- a second resolution could disagree with it. An unreadable
-- schema fails loud: an unverifiable engine is not written.
-- The check is domain-blind: 'checkEmits' takes a typed schema, and the NixOS
-- specifics live in 'Lips.Nix.Options'.
assertOptionsAdmissible :: Target -> FilePath -> FilePath -> EngineData -> IO ()
assertOptionsAdmissible target schemaPath file eng = do
  mbytes <- try (BL.readFile schemaPath) :: IO (Either IOException BL.ByteString)
  case mbytes of
    Left e -> die (report
      ("lips can't read the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
      [tshow e]
      "→ run generate again.")
    Right bytes -> case schemaFor target bytes of
      Left why -> die (report
        ("lips can't parse the " <> targetSlug target <> " option schema at " <> T.pack schemaPath <> ":")
        [why]
        "→ run generate again.")
      Right schema -> case checkEmits schema (edRules eng) of
        []   -> pure ()
        errs -> die (validationReport file
          ("its rules use " <> targetSlug target <> " options that don't exist or have the wrong type:\n"
            <> T.unlines (map (("  - " <>) . renderOptionError) errs)))

-- | Locate the target world's @options.json@, and say WHICH schema that is:
-- the returned pin is what @.generation@ records, so grounding stops being
-- invisible after the mint.
--
-- Precedence is by explicitness. @--schema \<flakeref\>@ (a caller whose own
-- world is not the one lips was built against) beats @LIPS_OPTIONS_JSON@ (a
-- prebuilt document: the suite's offline fixture), which beats the flakeref
-- baked into the packaged binary -- the zero-configuration default, so nobody
-- has to author a pin to run generate at all.
--
-- A flakeref is resolved through @nix flake metadata@ and both BUILT and
-- RECORDED as the locked url nix reports, so the pin cannot float: recording
-- @nixpkgs@ or a branch name would name a different schema every week and the
-- record would lie about what admitted the rules. A supplied document has no
-- ref, so it is pinned by content instead ('genId' over its bytes).
--
-- The build is announced, since the first one evaluates the whole NixOS manual
-- (~11 MB) before nix caches it; every later generate is a store cache hit. Only
-- generate and the read-only @options@ lookup pay this -- compile\/check never
-- touch the schema.
--
-- @remedy@ is the invocation to suggest when the schema cannot be had; it is a
-- parameter because this function serves two verbs and knows about neither.
ensureOptionSchema :: Target -> Maybe String -> Text -> IO (FilePath, Text)
ensureOptionSchema target (Just ref) remedy = do
  locked <- lockFlakeRef ref remedy
  path <- buildOptionSchema target locked remedy
  pure (path, locked)
ensureOptionSchema target Nothing remedy = do
  override <- lookupEnv "LIPS_OPTIONS_JSON"
  case override of
    -- Pinned by content: a path names a file that changes, so the record would
    -- say nothing checkable. The hash is the same function the record's own id
    -- uses, so one hash function serves the whole provenance story.
    Just p  -> do
      mbytes <- try (BS.readFile p) :: IO (Either IOException BS.ByteString)
      case mbytes of
        Left e -> die (report
          ("lips can't read the option schema at " <> T.pack p <> " (LIPS_OPTIONS_JSON):")
          [tshow e]
          ("→ point LIPS_OPTIONS_JSON at a readable options.json, or unset it: " <> remedy))
        Right bytes -> pure (p, "options-json:" <> hashBytes bytes)
    Nothing -> do
      -- The world's own env var, set by the packaged binary from lips's flake
      -- lock. Unset means no schema source is configured at all.
      mflake <- lookupEnv (bakedPinVar target)
      case mflake of
        Nothing -> die (report
          ("lips can't read the setup's options: no " <> targetSlug target <> " option schema source is configured.")
          ["none of --schema, LIPS_OPTIONS_JSON or " <> T.pack (bakedPinVar target) <> " is set."]
          ("→ run the packaged lips: nix run . -- " <> remedy <> " (it bakes the pinned flakes)."))
        Just flakeref -> do
          locked <- lockFlakeRef flakeref remedy
          path <- buildOptionSchema target locked remedy
          pure (path, locked)

-- | The env var carrying the flakeref baked into the packaged binary for one
-- world. Per world, because each world's schema comes from its own flake.
bakedPinVar :: Target -> String
bakedPinVar Nixos       = "LIPS_NIXPKGS_FLAKE"
bakedPinVar HomeManager = "LIPS_HM_FLAKE"
bakedPinVar Kubenix     = "LIPS_KUBENIX_FLAKE"
bakedPinVar Terranix    = "LIPS_TERRANIX_FLAKE"

-- | Resolve any flakeref to the LOCKED url nix reports for it, which is then
-- both built and recorded. Asking nix (rather than inspecting the ref's shape)
-- keeps one authority for what a ref locks to: @flake:nixpkgs@, a branch, a
-- @path:@ working tree and an already-pinned @github:owner\/repo\/\<rev\>@ all
-- come back naming fixed content.
lockFlakeRef :: String -> Text -> IO Text
lockFlakeRef ref remedy = do
  res <- try (readProcessWithExitCode "nix" ["flake", "metadata", "--json", ref] "")
  case res of
    Left e -> die (report
      "lips needs nix to resolve the option schema's flake, but couldn't run it:"
      (T.lines (tshow (e :: IOException)))
      ("→ install nix, or run lips through it: nix run . -- " <> remedy))
    Right (ExitFailure _, _, err) -> die (report
      ("lips can't resolve the option schema's flake " <> T.pack ref <> ":")
      (T.lines (T.pack err))
      "→ pass a flakeref nix can fetch, e.g. --schema github:NixOS/nixpkgs/nixos-24.11.")
    Right (ExitSuccess, out, _) -> case lockedUrl (BLC.pack out) of
      Just u  -> pure u
      -- Deduce-or-fail: without the locked url the record could only name the
      -- ref the caller typed, which may float. Refuse rather than record that.
      Nothing -> die (report
        ("lips can't tell what " <> T.pack ref <> " locks to: nix reported no locked url.")
        []
        "→ update nix, or pass an already-pinned ref (github:owner/repo/<rev>).")

-- | The @url@ field of @nix flake metadata --json@: nix's own locked form of the
-- ref it was given.
lockedUrl :: BL.ByteString -> Maybe Text
lockedUrl bytes = do
  Object o <- decode bytes
  String u <- KM.lookup "url" o
  pure u

-- | Build one world's optionsJSON from a locked flakeref and return the path of
-- the document inside it.
buildOptionSchema :: Target -> Text -> Text -> IO FilePath
buildOptionSchema target locked remedy = step (targetSlug target <> " option schema") $ do
  -- The pin without nix's hash query, which is half a line of noise a reader
  -- never types back in.
  note ("pinned flake " <> T.takeWhile (/= '?') locked)
  -- On the live line, not as a note: a cache hit takes a second, and a warning
  -- about minutes that stays on screen afterwards is a line that misinforms.
  setState "a cache miss evaluates the whole manual, which takes minutes"
  built <- try (readProcessWithExitCode "nix"
    [ "build", "--impure", "--no-link", "--print-out-paths"
    , "--expr", T.unpack (schemaExpr target (T.unpack locked)) ] "")
  case built of
    Left e -> die (report
      "lips needs nix to build the option schema, but couldn't run it:"
      (T.lines (tshow (e :: IOException)))
      ("→ install nix, or run lips through it: nix run . -- " <> remedy))
    Right (ExitFailure _, _, err) -> die (report
      ("lips couldn't build the " <> targetSlug target <> " option schema:")
      (T.lines (T.pack err))
      ("→ run it again: nix run . -- " <> remedy))
    Right (ExitSuccess, out, _) ->
      pure (T.unpack (T.strip (T.pack out)) <> schemaSubPath target)

-- | Where the options document sits inside the built derivation. The JSON shape
-- is identical across worlds (all are nixosOptionsDoc output); only the path
-- differs -- and kubenix and terranix, whose documents lips builds itself with
-- nixosOptionsDoc, inherit that helper's NixOS default path.
schemaSubPath :: Target -> FilePath
schemaSubPath Nixos       = "/share/doc/nixos/options.json"
schemaSubPath HomeManager = "/share/doc/home-manager/options.json"
schemaSubPath Kubenix     = "/share/doc/nixos/options.json"
schemaSubPath Terranix    = "/share/doc/nixos/options.json"

-- | The Nix expression producing the target world's optionsJSON derivation.
-- NixOS: the pinned nixpkgs NixOS manual optionsJSON (the same options.json
-- search.nixos.org is built from). home-manager: the pinned home-manager
-- flake's docs-json. Both are the same optionsJSON shape, so only the
-- derivation differs. Pins via @builtins.getFlake@; @--impure@ covers
-- @builtins.currentSystem@.
schemaExpr :: Target -> String -> Text
schemaExpr Nixos flakeref = T.pack $ concat
  [ "let np = builtins.getFlake \"", flakeref, "\"; in "
  , "(import (np.outPath + \"/nixos\") "
  , "{ configuration = {}; system = builtins.currentSystem; })"
  , ".config.system.build.manual.optionsJSON" ]
schemaExpr HomeManager flakeref = T.pack $ concat
  [ "let hm = builtins.getFlake \"", flakeref, "\"; in "
  , "hm.packages.${builtins.currentSystem}.docs-json" ]
-- kubenix declares its Kubernetes resource fields as module options generated
-- from the Kubernetes API, so the document comes from nixosOptionsDoc over an
-- otherwise EMPTY kubenix evaluation: the option TREE is what grounds a rule,
-- and no program's own values may enter the schema.
-- nixpkgs comes from the kubenix flake's OWN pinned input, never resolved
-- ambiently: a grounding schema must be reproducible from the recorded ref
-- alone.
schemaExpr Kubenix flakeref = T.pack $ concat
  [ "let k = builtins.getFlake \"", flakeref, "\"; "
  , "system = builtins.currentSystem; "
  , "pkgs = import k.inputs.nixpkgs { inherit system; }; "
  , "e = k.evalModules.${system} { module = { kubenix, ... }: "
  , "{ imports = [ kubenix.modules.k8s ]; }; }; in "
  , "(pkgs.nixosOptionsDoc { options = e.options; warningsAreErrors = false; }).optionsJSON" ]
-- terranix publishes @lib.terranixOptions@, but that helper documents the
-- USER's modules: its jq pass deletes resource, data, provider, output and
-- every other core namespace, which are exactly the paths a program writes. So
-- lips evaluates terranix's own core modules and runs nixosOptionsDoc over
-- them, the same mechanism the other worlds use. The lib.extend mirrors
-- terranix's core/default.nix, whose modules use those lib helpers.
schemaExpr Terranix flakeref = T.pack $ concat
  [ "let t = builtins.getFlake \"", flakeref, "\"; "
  , "system = builtins.currentSystem; "
  , "pkgs = import t.inputs.nixpkgs { inherit system; }; "
  , "lib = pkgs.lib.extend (import (t + \"/core/helpers.nix\") pkgs); "
  , "e = lib.evalModules { modules = [ "
  , "{ imports = [ (t + \"/core/terraform-options.nix\") (t + \"/modules\") ]; } "
  , "{ _module.args = { inherit pkgs; }; } ]; }; in "
  , "(pkgs.nixosOptionsDoc { options = e.options; warningsAreErrors = false; }).optionsJSON" ]
