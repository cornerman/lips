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
  ( RealizeError (..)
  , realize
  ) where

import           Data.Char       (isAlpha, isAlphaNum, isSpace)
import           Data.List       (partition, sortOn)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base         (Base, Conflict, resolve)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Value  (Piece (..), Value (..), parseValue)

-- | Why a ground base could not be projected to a module. Every case is an
-- engine defect (a minted rule that emitted an ill-formed artifact group or a
-- reference to an artifact nothing builds), surfaced as a value the caller
-- reports, never a crash -- 'realize' is on the deterministic @print@ path.
data RealizeError
  = -- | Equal-strength contradictions block realization (both provenances travel).
    RConflicts [Conflict]
  | -- | @${artifact.<name>}@ references to artifacts no group builds.
    RDangling [Text]
  | -- | A malformed artifact group: the artifact name and the reason.
    RBadArtifact Text Text
  deriving (Eq, Show)

-- | Realize a base to a NixOS module, or report why it cannot. Deterministic:
-- assignments are ordered by option path, so the same base always yields
-- byte-identical text.
realize :: Base -> Either RealizeError Text
realize base = do
  winners <- either (Left . RConflicts) Right (resolve base)
  renderModule (Map.toList winners)

-- | An artifact group is any decision whose subject is rooted at @artifact@
-- (@artifact.<name>.builder@, @artifact.<name>.args.<key>@). These do not
-- become option assignments; realize gathers them into a @let@-bound
-- derivation the module can reference as @${artifact.<name>}@.
renderModule :: [(Subject, Decision)] -> Either RealizeError Text
renderModule winners =
  let (arts, opts) = partition (rootedAtArtifact . fst) winners
      defined  = [ n | (Subject ("artifact" : n : _), _) <- arts ]
      refs     = concatMap (artifactRefs . unAssertion . dAssertion . snd) opts
      dangling = [ r | r <- refs, r `notElem` defined ]
   in if not (null dangling)
        -- Deduce-or-fail: never emit a module that references an artifact no
        -- group builds. An engine bug, so it fails loud naming the culprits.
        then Left (RDangling dangling)
        else do
          entries <- artifactEntries arts
          Right $ T.unlines $
            [ "# lips-realized NixOS module. Generated from a ground decision base; do not edit."
            , "{ config, lib, pkgs, ... }:"
            ]
              ++ letBlock entries
              ++ ["{"]
              ++ concatMap assignment (sortOn (path . fst) opts)
              ++ ["}"]

-- | Artifact names a rendered value references, in either realized form: a
-- bare @artifact.<name>@ standing as a value (a list element or top-level),
-- or a @${artifact.<name>}@ interpolation inside a string. Quote-aware, so the
-- literal token @artifact.@ appearing as plain text inside a string is not
-- mistaken for a reference (only @${artifact.@ counts there).
artifactRefs :: Text -> [Text]
artifactRefs = outside
  where
    -- Outside a string, bare values are whitespace/bracket-separated tokens; a
    -- token that STARTS with `artifact.` is a real reference. Matching only at
    -- a token boundary (not any offset) is what keeps a package path whose own
    -- segment happens to be @artifact@ (e.g. @pkgs.x.artifact.y@) from being
    -- misread as a reference and failing realize with a bogus dangling error.
    outside s = case T.uncons s of
      Nothing        -> []
      Just ('"', r)  -> inside r
      Just (c, r)
        | isSpace c || c == '[' || c == ']' -> outside r
        | otherwise ->
            let (tok, r') = T.break boundary s
             in case T.stripPrefix "artifact." tok of
                  Just nm -> name nm : outside r'
                  Nothing -> outside r'
    -- Inside a string only a `${artifact.<name>}` interpolation is a reference;
    -- an escaped char is skipped so a `\"` does not end the string early.
    inside s = case T.uncons s of
      Nothing         -> []
      Just ('\\', r)  -> inside (T.drop 1 r)
      Just ('"', r)   -> outside r
      Just ('$', r) | Just b <- T.stripPrefix "{artifact." r -> name b : inside (rest b)
      Just (_, r)     -> inside r
    boundary c = isSpace c || c == ']' || c == '"'
    name = T.takeWhile isNameChar
    rest = T.dropWhile isNameChar
    isNameChar c = c `elem` ("-_" :: String) || isAlphaNum c

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
-- so output is deterministic. A group whose subject carries no @<name>@
-- segment, or a malformed builder, is an engine defect returned as
-- 'RBadArtifact', never a crash.
artifactEntries :: [(Subject, Decision)] -> Either RealizeError [Text]
artifactEntries arts = do
  named <- traverse withName arts
  let groups = Map.toList (Map.fromListWith (++) [(n, [sd]) | (n, sd) <- named])
  concat <$> traverse entry groups
  where
    withName sd@(Subject ("artifact" : n : _), _) = Right (n, sd)
    withName (Subject segs, _) =
      Left (RBadArtifact (T.intercalate "." segs) "artifact decision has no <name> segment")
    entry (n, parts) = do
      b <- builderOf n parts
      Right $
        [ n <> " = pkgs." <> b <> " {" ]
          ++ [ "  " <> T.intercalate "." k <> " = " <> unAssertion (dAssertion d) <> ";"
             | (Subject ("artifact" : _ : "args" : k), d) <- sortOn fst parts ]
          ++ [ "};" ]

-- | The builder is a plain string naming a dotted path under @pkgs@; realize
-- splices it as @pkgs.<path>@ (a function, not a string). A missing or
-- malformed builder is an engine defect returned as 'RBadArtifact'.
builderOf :: Text -> [(Subject, Decision)] -> Either RealizeError Text
builderOf n parts =
  case [ dAssertion d | (Subject ("artifact" : _ : "builder" : _), d) <- parts ] of
    (Assertion a : _) -> case parseValue a of
      Right (VStr [PLit p]) | validBuilderPath p -> Right p
      _ -> Left (RBadArtifact n ("builder must be a plain string naming a pkgs path, got " <> a))
    [] -> Left (RBadArtifact n "no builder")
  where
    validBuilderPath p = not (T.null p) && T.all (\c -> c `elem` (".-_" :: String) || isAlphaNum c) p

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
path (Subject segs) = T.intercalate "." (map quoteSeg segs)

-- | Render one attribute-path segment: bare when it is a valid Nix identifier,
-- string-quoted otherwise. A value-keyed segment (e.g. a route path bound to an
-- @attrsOf@ key) carries characters like @/@ that a bare identifier cannot, so
-- it becomes @"..."@; the quoted form also escapes @\@ and @"@ so a program
-- value can never break out of the attribute name.
quoteSeg :: Text -> Text
quoteSeg s
  | isBareIdent s = s
  | otherwise     = "\"" <> esc s <> "\""
  where esc = T.replace "\"" "\\\"" . T.replace "\\" "\\\\"

isBareIdent :: Text -> Bool
isBareIdent s = case T.uncons s of
  Nothing      -> False
  Just (c, cs) -> (isAlpha c || c == '_') && T.all identChar cs
  where identChar c = isAlphaNum c || c `elem` ("_'-" :: String)

provComment :: Provenance -> Text
provComment (FromSource (SourceLoc f n)) = f <> ":" <> T.pack (show n)
provComment (Derived ids (RuleId r)) =
  "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r
provComment (FromGeneration gid) = "gen:" <> gid
