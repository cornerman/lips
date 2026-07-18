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

import           Data.List       (sortOn)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base     (Base, Conflict, resolve)
import Lips.Kernel.Decision

-- | Realize a base to a NixOS module, or report the conflicts that block it.
-- Deterministic: assignments are ordered by option path, so the same base
-- always yields byte-identical text.
realize :: Base -> Either [Conflict] Text
realize base = renderModule . Map.toList <$> resolve base

renderModule :: [(Subject, Decision)] -> Text
renderModule winners =
  T.unlines $
    [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
    , "{ config, lib, pkgs, ... }:"
    , "{"
    ]
      ++ concatMap assignment (sortOn (path . fst) winners)
      ++ ["}"]

-- | One option assignment, preceded by a provenance comment so any line is
-- traceable to the decision that produced it (spec section 2, provenance).
assignment :: (Subject, Decision) -> [Text]
assignment (subj, d) =
  [ "  # " <> provComment (dProv d)
  , "  " <> path subj <> " = " <> unAssertion (dAssertion d) <> ";"
  ]
  where
    unAssertion (Assertion a) = a

path :: Subject -> Text
path (Subject segs) = T.intercalate "." segs

provComment :: Provenance -> Text
provComment (FromSource (SourceLoc f n)) = f <> ":" <> T.pack (show n)
provComment (Derived ids (RuleId r)) =
  "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r
