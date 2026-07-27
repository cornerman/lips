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
  , realizeReplace
  , realizeArtifactFile
  ) where

import           Data.Char       (isAlpha, isAlphaNum)
import           Data.List       (nub, partition, sortOn)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base         (Base, Conflict, MergeMode (..), ResolveErr (..), resolve)
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Value  (Piece (..), Value (..), parseValue, renderRealized,
                                  valueArtifactNames)

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
  | -- | An option assertion that is not a canonical 'Value' (an engine defect;
    --    after the R1 canonical-storage refactor every assertion must re-parse).
    RMalformed Subject Text
  deriving (Eq, Show)

-- | Realize a base to a NixOS module, or report why it cannot. The merge
-- config (which subjects append vs. replace) and the assembly function are
-- injected, so this module needs no 'Value' dependency and no cycle: the
-- caller derives both from the engine's rule emits at run time (the kernel
-- stays domain-blind). Deterministic: assignments are ordered by option
-- path, so the same base always yields byte-identical text.
realize :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
        -> Base -> Either RealizeError Text
realize modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs -> Left (resolveErr errs)
    Right winners -> renderModule (Map.toList winners)

-- | A subject is either Replace or Append, so its failure is exactly one kind;
-- across subjects the kinds can mix. Report every conflict (the author's to
-- edit); if there are none, the first assembly defect (an engine bug). Never
-- silent: resolve returns Left only with a non-empty list, so the final branch
-- is unreachable in practice. Shared by 'realize' and 'realizeArtifactFile'.
resolveErr :: [ResolveErr] -> RealizeError
resolveErr errs =
  case [ c | REConflict c <- errs ] of
    cs@(_ : _) -> RConflicts cs
    []         -> case [ (s, e) | REAssemble s e <- errs ] of
                    ((s, e) : _) -> RMalformed s e
                    []            -> RConflicts []

-- | Render the program's artifacts as a standalone @artifact.nix@ file:
-- @{ pkgs }: { \<name\> = pkgs.\<builder\> { ... }; }@. This is the exact same
-- derivation the module @let@-binds (via 'artifactEntries'), extracted so a
-- compiled directory's flake can address each artifact as a buildable package
-- without re-deriving it (one authoritative rendering, from one ground base).
-- 'Nothing' when the program declares no artifacts, so an artifact-free
-- compile writes no such file. Pass the same /ground/ base 'realize' takes.
-- Returns the file body paired with the artifact names (the attrset keys), so
-- the caller can print exact @#artifact.\<name\>@ commands without re-parsing.
realizeArtifactFile :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                    -> Base -> Either RealizeError (Maybe (Text, [Text]))
realizeArtifactFile modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners ->
      let arts  = filter (rootedAtArtifact . fst) (Map.toList winners)
          names = nub [ n | (Subject ("artifact" : n : _), _) <- arts ]
      in if null arts
           then Right Nothing
           else do
             entries <- artifactEntries arts
             let body = T.unlines (
                   [ "# lips-realized artifact derivations. Generated; do not edit."
                   , "{ pkgs }:"
                   , "{"
                   ] ++ map ("  " <>) entries ++ ["}"])
             Right (Just (body, names))

-- | Today's all-Replace behavior, for callers and tests that do not
-- aggregate. Byte-identical to the pre-aggregation 'realize'.
realizeReplace :: Base -> Either RealizeError Text
realizeReplace = realize (const Replace) (\_ -> Left "assemble unused")

-- | An artifact group is any decision whose subject is rooted at @artifact@
-- (@artifact.<name>.builder@, @artifact.<name>.args.<key>@). These do not
-- become option assignments; realize gathers them into a @let@-bound
-- derivation the module can reference as @${artifact.<name>}@.
renderModule :: [(Subject, Decision)] -> Either RealizeError Text
renderModule winners = do
  let (arts, opts) = partition (rootedAtArtifact . fst) winners
      defined  = [ n | (Subject ("artifact" : n : _), _) <- arts ]
  -- Each option assertion is canonical 'Value' text (stored by 'fillValue'),
  -- so parse it once: the Value drives both artifact-reference detection
  -- (structural, not text-scanned) and the single canonical->Nix render. A
  -- non-Value assertion is an engine defect (RMalformed), never spliced raw.
  optVals <- traverse parseOpt opts
  let refs     = concatMap (valueArtifactNames . valOf) optVals
      dangling = [ r | r <- refs, r `notElem` defined ]
  if not (null dangling)
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
          ++ concatMap assignment (sortOn (path . subjOf) optVals)
          ++ ["}"]
  where
    subjOf (s, _, _) = s
    valOf  (_, _, v) = v
    parseOpt (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Right v
        | isUnfilledTail v -> Left (RMalformed s "unfilled <value.tail> reached realize (a tail hole must be filled to a list before storage; a non-firing rule stores nothing)")
        | otherwise        -> Right (s, d, v)
      Left e   -> Left (RMalformed s e)
    -- An unfilled VTail is structurally unreachable in production (fillValue
    -- converts VTail -> VList at the refine door; a non-firing rule emits no
    -- decision), but "fail loud, never guess" is a kernel invariant, so a
    -- future path that let one slip through is caught here rather than
    -- rendering the literal "<value.tail>" into a module (renderRealized's
    -- catch-all would otherwise emit it).
    isUnfilledTail (VTail _ _) = True
    isUnfilledTail _           = False

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
    -- An artifact name is a template (literal text with <self>/<capture>
    -- occurrences); by the time realize runs, both binding passes have gone, so
    -- any token left is a name nothing ever bound. Stop here: the attrset key
    -- is spliced into Nix verbatim, and the dangling-reference check compares
    -- names as text, so an unfilled ref matches its unfilled group and would
    -- pass. This guard is the only thing between an unbound name and a module
    -- containing the literal "<self>-core = pkgs.buildGoModule {".
    withName sd@(Subject ("artifact" : n : _), _) = case nameTokens n of
      (t : _) -> Left (RBadArtifact n ("artifact name reached realize with the token <" <> t
                                        <> "> unfilled; a <self> binds per instance and a"
                                        <> " <capture> per rule match, so this name was never bound"))
      []      -> Right (n, sd)
    withName (Subject segs, _) =
      Left (RBadArtifact (T.intercalate "." segs) "artifact decision has no <name> segment")
    entry (n, parts) = do
      b <- builderOf n parts
      argLines <- traverse argLine (sortOn fst [ (k, d) | (Subject ("artifact" : _ : "args" : k), d) <- parts ])
      Right $
        [ n <> " = pkgs." <> b <> " {" ]
          ++ argLines
          ++ [ "};" ]
    -- One artifact arg: its path and the realized Nix of its (canonical)
    -- Value assertion. A non-Value arg is an engine defect, loud.
    argLine (k, d) = case parseValue (unAssertion (dAssertion d)) of
      Right v  -> Right ("  " <> T.intercalate "." k <> " = " <> renderRealized v <> ";")
      Left e   -> Left (RMalformed (dSubject d) e)

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
-- The value is the pre-parsed 'Value', rendered to Nix once here (the single
-- canonical->Nix render point), so artifact refs render bare and strings stay
-- quoted.
assignment :: (Subject, Decision, Value) -> [Text]
assignment (subj, d, v) =
  [ "  # " <> provComment (dProv d)
  , "  " <> path subj <> " = " <> renderRealized v <> ";"
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
