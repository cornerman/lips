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
  , realizeArtifactFile
  , realizeStagedPaths
  , realizeArtifactPaths
  , realizeArtifactFills
  , realizeClaims
  ) where

import           Data.Char       (isAlpha, isAlphaNum)
import           Data.List       (nub, partition, sortOn)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base         (Base, Conflict, MergeMode (..), ResolveErr (..), resolve)
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Claim        (Claim, claimRooted, claimsFromDecisions)
import Lips.Kernel.Decision
import Lips.Kernel.Source       (validMarker)
import Lips.Kernel.Engine.Value  (Piece (..), Value (..), parseValue, renderRealized,
                                  sourceText, valueArtifactNames, valueArtifactPaths,
                                  valuePaths)

-- | Why a ground base could not be projected to a module. Every case is an
-- engine defect (a minted rule that emitted an ill-formed artifact group or a
-- reference to an artifact nothing builds), surfaced as a value the caller
-- reports, never a crash -- 'realize' is on the deterministic @compile@ path.
data RealizeError
  = -- | Equal-strength contradictions block realization (both provenances travel).
    RConflicts [Conflict]
  | -- | @${artifact.<name>}@ references to artifacts no group builds.
    RDangling [Text]
  | -- | A malformed artifact group: the artifact name and the reason.
    RBadArtifact Text Text
  | -- | A malformed claim group, in plain words (an unknown section, a claim
    --   with no command, a stdin\/stdout with no text form).
    RBadClaim Text
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

-- | For every artifact, the one @bin/<x>@ name the ground base itself names
-- inside it (anywhere a value holds @${artifact.\<name\>}/bin/\<x\>@ -- an
-- ExecStart, a wrapper's own arg naming its core). @nix run@/@nix develop@'s
-- implicit program lookup assumes @bin/\<pname\>@; a builder is free to name
-- its output differently (a go.mod's @module@, a Cargo @[[bin]] name@), so
-- that assumption silently breaks whenever the two diverge -- exactly the
-- "knowing the answer requires looking inside the result" case 'artifactGate'
-- (the online build gate) already documents. Nothing here builds anything or
-- knows a language: it only repeats a name the base's OWN decisions already
-- spell out, the same way a @${pkgs.\<path\>}@ reference is forwarded without
-- understanding it. Deduce-or-fail: an artifact named by zero or by more than
-- one distinct @bin/\<x\>@ is left out, so nix's unchanged default applies
-- exactly as it does today -- never a guess between two candidates.
mainPrograms :: [(Subject, Decision)] -> Either RealizeError (Map.Map Text Text)
mainPrograms winners = do
  vals <- traverse parseOne winners
  let bins = [ (n, b) | (_, v) <- vals, (n, p) <- valueArtifactPaths v, Just b <- [binName p] ]
  Right (Map.mapMaybe onlyOne (Map.fromListWith (++) [ (n, [b]) | (n, b) <- bins ]))
  where
    parseOne (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Right v -> Right (s, v)
      Left e  -> Left (RMalformed s e)
    -- A path exactly one segment under bin/, nothing more (a flag-bearing
    -- ExecStart like "/bin/hello --port 8080" already stops at the space via
    -- 'valueArtifactPaths', so this only guards a deeper path like /bin/x/y).
    binName p = case T.splitOn "/" p of
      ["", "bin", b] | not (T.null b) -> Just b
      _                                -> Nothing
    onlyOne bs = case nub bs of
      [b] -> Just b
      _   -> Nothing

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
             requireDefined names =<< artifactArgRefs arts
             mp <- mainPrograms (Map.toList winners)
             entries <- artifactEntries mp arts
             -- The same @let artifact = { ... }@ shape the module uses, for the
             -- same reason: an arg may hold @${artifact.<other>}@, which
             -- 'renderRealized' emits bare as @artifact.<other>@, so the name
             -- @artifact@ must be in scope and its binding recursive. A plain
             -- attrset would render an undefined variable.
             let body = T.unlines (
                   [ "# lips-realized artifact derivations. Generated; do not edit."
                   , "{ pkgs }:"
                   ] ++ letBlock entries ++ ["artifact"])
             Right (Just (body, names))

-- | The claims a ground base states: the observables the author supplied,
-- projected exactly like the artifacts beside them (same resolve, same base), so
-- what @check@ runs and what the module contains can never disagree.
realizeClaims :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
              -> Base -> Either RealizeError [Claim]
realizeClaims modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> either (Left . RBadClaim) Right
                            (claimsFromDecisions (Map.toList winners))

-- | Every RELATIVE path the realized base names, paired with the decision that
-- named it. Nix resolves such a path against the module directory, i.e. against
-- the tree lips stages beside the module (an artifact's minted source), so it
-- is the one value the module cannot vouch for itself: a path naming nothing
-- dies inside nix, with an error naming neither lips, the program, nor a
-- remedy. The kernel is pure and owns no filesystem, so it reports the paths
-- and the caller requires each to exist (deduce-or-fail, at the door that
-- stages). An absolute path names a file on the host, which is the host's to
-- have, not lips's to check.
realizeStagedPaths :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                   -> Base -> Either RealizeError [(Text, Decision)]
realizeStagedPaths modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> concat <$> traverse paths (Map.toList winners)
  where
    paths (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Left e  -> Left (RMalformed s e)
      Right v -> Right [ (p, d) | p <- valuePaths v, isRelative p ]
    isRelative p = T.isPrefixOf "./" p || T.isPrefixOf "../" p

-- | Every path the realized base names INSIDE an artifact:
-- @(artifact, \/rel\/path, the decision that named it)@. Twin of
-- 'realizeStagedPaths' one level in: a staged path must exist BESIDE the module,
-- an artifact path must exist INSIDE the build. Neither is knowable from the
-- module text -- what a build contains is decided by its source, and a binary's
-- name is spelled in a go.mod or a Cargo.toml, not in the derivation -- so the
-- kernel reports the pairs and the caller that owns nix builds the artifact and
-- looks. Both artifact groups' own args and option values are scanned, since a
-- wrapper's script names its core's binary exactly as a unit's ExecStart does.
realizeArtifactPaths :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                     -> Base -> Either RealizeError [(Text, Text, Decision)]
realizeArtifactPaths modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> concat <$> traverse paths (Map.toList winners)
  where
    paths (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Left e  -> Left (RMalformed s e)
      Right v -> Right [ (n, p, d) | (n, p) <- valueArtifactPaths v ]

-- | Every source fill the engine declares: @(artifact, marker, text)@ from
-- @artifact.\<name\>.fill.\<marker\>@. The kernel owns no filesystem, so it
-- reports what must be substituted and the caller applies it to the tree it
-- stages (like 'realizeStagedPaths'). A fill whose value has no text form, or
-- whose marker could never appear in source, is an engine defect, loud: source
-- is text, and lips fills it offline, so a store path is not available to write.
realizeArtifactFills :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                     -> Base -> Either RealizeError [(Text, Text, Text)]
realizeArtifactFills modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> traverse one [ sd | sd@(Subject ("artifact" : _ : "fill" : _), _) <- Map.toList winners ]
  where
    one (s@(Subject (_ : n : _ : marker)), d) = do
      m <- case marker of
        [m] | validMarker m -> Right m
        _ -> Left (RBadArtifact n ("fill " <> T.intercalate "." marker
              <> " is not a source marker name (one segment, starting with a letter,"
              <> " of letters, digits, _ or -), so no source file could name it"))
      case parseValue (unAssertion (dAssertion d)) of
        Left e  -> Left (RMalformed s e)
        Right v -> case sourceText v of
          Just t  -> Right (n, m, t)
          Nothing -> Left (RBadArtifact n ("fill " <> m <> " has no source text: "
                      <> unAssertion (dAssertion d)
                      <> " (a fill writes text into source, so a reference, list"
                      <> " or attrset cannot be one)"))
    one (s, _) = Left (RMalformed s "artifact fill without a marker segment")

-- | An artifact group is any decision whose subject is rooted at @artifact@
-- (@artifact.<name>.builder@, @artifact.<name>.args.<key>@). These do not
-- become option assignments; realize gathers them into a @let@-bound
-- derivation the module can reference as @${artifact.<name>}@.
renderModule :: [(Subject, Decision)] -> Either RealizeError Text
renderModule winners = do
  let (arts, rest) = partition (rootedAtArtifact . fst) winners
      -- A claim is kernel vocabulary like an artifact: it is OBSERVED, not
      -- assigned, so it must not become an option. Without this it would render
      -- as `claim.echo.run = "...";`, a path no target world declares, and the
      -- module would fail to evaluate wherever it was imported.
      opts = [ sd | sd@(Subject segs, _) <- rest, not (claimRooted segs) ]
      defined  = [ n | (Subject ("artifact" : n : _), _) <- arts ]
  -- Each option assertion is canonical 'Value' text (stored by 'fillValue'),
  -- so parse it once: the Value drives both artifact-reference detection
  -- (structural, not text-scanned) and the single canonical->Nix render. A
  -- non-Value assertion is an engine defect (RMalformed), never spliced raw.
  optVals <- traverse parseOpt opts
  -- An artifact reference can stand in an option value OR in another
  -- artifact's arg (the core-plus-wrapper shape), so both are checked: a
  -- reference missed here dies inside nix as "attribute '<name>' missing",
  -- naming neither lips, the program, nor a remedy.
  argRefs <- artifactArgRefs arts
  requireDefined defined (concatMap (valueArtifactNames . valOf) optVals ++ argRefs)
  mp <- mainPrograms winners
  entries <- artifactEntries mp arts
  Right $ T.unlines $
    [ "# lips-realized module. Generated from a ground decision base; do not edit."
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

-- | The artifact names referenced from artifact groups' own args, so a
-- wrapper naming its core is checked like any other reference. A non-'Value'
-- arg is an engine defect, loud (the same parse 'artifactEntries' makes).
artifactArgRefs :: [(Subject, Decision)] -> Either RealizeError [Text]
artifactArgRefs arts =
  concat <$> traverse refs [ sd | sd@(Subject ("artifact" : _ : "args" : _), _) <- arts ]
  where
    refs (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Left e  -> Left (RMalformed s e)
      Right v -> Right (valueArtifactNames v)

-- | Deduce-or-fail: never emit Nix that references an artifact no group
-- builds. An engine bug, so it fails loud naming every culprit once.
requireDefined :: [Text] -> [Text] -> Either RealizeError ()
requireDefined defined refs =
  case nub [ r | r <- refs, r `notElem` defined ] of
    []       -> Right ()
    dangling -> Left (RDangling dangling)

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
artifactEntries :: Map.Map Text Text -> [(Subject, Decision)] -> Either RealizeError [Text]
artifactEntries mainProgs arts = do
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
      -- A section the kernel does not know would be silently dropped: the args
      -- and builder selectors below simply would not match it, so a mint's typo
      -- (args' -> arg) or an invented mechanism would compile to a derivation
      -- missing what the engine meant to say.
      case nub [ sec | (Subject ("artifact" : _ : sec : _), _) <- parts
                     , sec `notElem` ["builder", "args", "fill"] ] of
        []   -> Right ()
        secs -> Left (RBadArtifact n ("unknown section(s) " <> T.intercalate ", " secs
                 <> "; an artifact has a builder, args and fill"))
      b <- builderOf n parts
      argLines <- traverse argLine (sortOn fst [ (k, d) | (Subject ("artifact" : _ : "args" : k), d) <- parts ])
      Right $
        [ n <> " = pkgs." <> b <> " {" ]
          ++ argLines
          ++ mainProgramLine n
          ++ [ "};" ]
    mainProgramLine n = case Map.lookup n mainProgs of
      Nothing -> []
      Just b  -> [ "  meta.mainProgram = " <> quoteBin b <> ";" ]
    quoteBin b = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" b) <> "\""
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
