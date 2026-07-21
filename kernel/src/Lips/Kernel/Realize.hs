{-# LANGUAGE OverloadedStrings #-}

-- | Realization: projecting a ground decision base to its target artifact, a
-- NixOS module (spec v2, section 10, \"NixOS module = canonical application
-- kind\"). This is the deterministic tail of @run@; no AI is involved.
--
-- The projection is direct because of two kernel choices: a 'Subject' is an
-- attribute path, which is exactly a NixOS option path, and the assertion
-- carries the Nix expression assigned to it. So each decision becomes one
-- @path = expr;@ assignment, and the base becomes a module.
--
-- Contract: pass a /ground/ base (post-refinement, all decisions are option
-- assignments). The realizer resolves it first and refuses to emit anything
-- while a conflict stands, so a contradiction never reaches an artifact.
-- Generated output is never hand-edited (spec section 9, item 1); the header
-- says so.
module Lips.Kernel.Realize
  ( realize
  ) where

import           Data.List       (partition, sortOn)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base         (Base, Conflict, resolve)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Value  (Piece (..), Value (..), parseValue)

-- | Realize a base to a NixOS module, or report the conflicts that block it.
-- Deterministic: assignments are ordered by option path, so the same base
-- always yields byte-identical text.
realize :: Base -> Either [Conflict] Text
realize base = renderModule . Map.toList <$> resolve base

-- | An artifact group is any decision whose subject is rooted at @artifact@
-- (@artifact.<name>.builder@, @artifact.<name>.args.<key>@). These do not
-- become option assignments; realize gathers them into a @let@-bound
-- derivation the module can reference as @${artifact.<name>}@.
renderModule :: [(Subject, Decision)] -> Text
renderModule winners =
  let (arts, opts) = partition (rootedAtArtifact . fst) winners
   in T.unlines $
        [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
        , "{ config, lib, pkgs, ... }:"
        ]
          ++ letBlock (artifactEntries arts)
          ++ ["{"]
          ++ concatMap assignment (sortOn (path . fst) opts)
          ++ ["}"]

rootedAtArtifact :: Subject -> Bool
rootedAtArtifact (Subject ("artifact" : _)) = True
rootedAtArtifact _                          = False

-- | Wrap the artifact bindings in @let artifact = { ... }; in@. The binding is
-- named @artifact@ so a stored @${artifact.<name>}@ reference resolves
-- directly, with no rewriting. Emitted only when there are artifacts, so an
-- artifact-free module is byte-identical to before.
letBlock :: [Text] -> [Text]
letBlock []      = []
letBlock entries =
  ["let", "  artifact = {"] ++ map ("    " <>) entries ++ ["  };", "in"]

-- | Render every @artifact.<name>@ group to its attrset field, in name order
-- so output is deterministic.
artifactEntries :: [(Subject, Decision)] -> [Text]
artifactEntries arts =
  concatMap entry (Map.toList (Map.fromListWith (++) [(name subj, [(subj, d)]) | (subj, d) <- arts]))
  where
    name (Subject (_ : n : _)) = n
    name (Subject _)           = error "artifact decision without a name"
    entry (n, parts) =
      [ n <> " = pkgs." <> builderOf n parts <> " {" ]
        ++ [ "  " <> T.intercalate "." k <> " = " <> unAssertion (dAssertion d) <> ";"
           | (Subject ("artifact" : _ : "args" : k), d) <- sortOn fst parts ]
        ++ [ "};" ]

-- | The builder is a plain string naming a dotted path under @pkgs@; realize
-- splices it as @pkgs.<path>@ (a function, not a string). A missing or
-- malformed builder is an engine bug, so it fails loud rather than emitting a
-- broken module.
builderOf :: Text -> [(Subject, Decision)] -> Text
builderOf n parts =
  case [ dAssertion d | (Subject ("artifact" : _ : "builder" : _), d) <- parts ] of
    (Assertion a : _) -> case parseValue a of
      Right (VStr [PLit p]) | validBuilderPath p -> p
      _ -> error ("artifact " <> T.unpack n <> ": builder must be a plain string naming a pkgs path, got " <> T.unpack a)
    [] -> error ("artifact " <> T.unpack n <> ": no builder")
  where
    validBuilderPath p = not (T.null p) && T.all (\c -> c `elem` (".-_" :: String) || isAlphaNum c) p
    isAlphaNum c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

unAssertion :: Assertion -> Text
unAssertion (Assertion a) = a

-- | One option assignment, preceded by a provenance comment so any line is
-- traceable to the decision that produced it (spec section 2, provenance).
assignment :: (Subject, Decision) -> [Text]
assignment (subj, d) =
  [ "  # " <> provComment (dProv d)
  , "  " <> path subj <> " = " <> unAssertion (dAssertion d) <> ";"
  ]

path :: Subject -> Text
path (Subject segs) = T.intercalate "." segs

provComment :: Provenance -> Text
provComment (FromSource (SourceLoc f n)) = f <> ":" <> T.pack (show n)
provComment (Derived ids (RuleId r)) =
  "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r
provComment (FromGeneration gid) = "gen:" <> gid
