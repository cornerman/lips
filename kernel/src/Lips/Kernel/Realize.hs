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
  , realizeClauseClaims
  , realizeClauses
  , unobservedClauses
  , defaultSiteName
  , siteNameIn
  , sitePropertiesIn
  ) where

import           Data.Char       (isAlpha, isAlphaNum)
import           Data.List       (nub, nubBy, partition, sortOn)

import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base         (Base, Conflict, MergeMode (..), ResolveErr (..), resolve, toList)
import Lips.Kernel.Clause.Gate  (Clause (..), faultText, gate, gateClaim, paramCount,
                                 reachedContracts)
import Lips.Kernel.Clause.Vocabulary (Contract (..), Vocabulary)
import Lips.Kernel.Capture      (nameTokens)
import Lips.Kernel.Claim        (Claim, ClauseClaim (..), claimRooted, claimsFromDecisions,
                                 clauseClaimsFromDecisions)
import Lips.Kernel.Decision
import Lips.Kernel.Sexp         (renderSexp, sexpSymbols)
import Lips.Kernel.Source       (validMarker)
import Lips.Kernel.Engine.Value  (Piece (..), Ref (..), Value (..), parseValue, renderRealized,
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
  | -- | The clause set does not pass the subset gate: a mint defect, reported
    --   in the gate's own words so the offending name travels.
    RBadClause Text
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

-- | Does this base state any behaviour at all? A value may name @${site}@ only
-- when there are clauses to build into one; otherwise the module would import a
-- directory compile never writes, and nix would die with a bare "path does not
-- exist" naming neither lips nor a remedy.
--
-- ROOTED, not well-formed: a malformed clause subject still states behaviour, and
-- 'realizeClauses' refuses it by name. Answering "no behaviour" here would report
-- the missing site instead of the real defect.
statesClauses :: [(Subject, Decision)] -> Bool
statesClauses = any (\(Subject segs, _) -> clauseRooted segs)

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
             argSite <- anyArgReferencesSite arts
             siteNm <- siteNameFrom (Map.toList winners) argSite
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
                   ] ++ letBlock siteNm entries ++ ["artifact"])
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

-- | The clause core a ground base states: every @clause.\<name\>@ decision,
-- gated, then rendered as one Scheme file.
--
-- Two things make this more than a concatenation. Order is the program's own:
-- clauses come out in source-line order, the same rule
-- 'Lips.Kernel.Engine.Aggregate' uses for list contributors, so a human reads
-- the file in the order they wrote the sentences. And each definition carries
-- the program lines that caused it, walked out of the provenance chain, which is
-- what makes invented behaviour visible instead of merely present.
--
-- 'Nothing' when the program states no clauses, so a configuration-only program
-- is untouched by the logic axis.
realizeClauses :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
               -> Vocabulary -> Base -> Base
               -> Either RealizeError (Maybe (Text, [Text], [(Text, Maybe Int)]))
realizeClauses modeOf assemble vocab source base =
  case resolve modeOf assemble base of
    Left errs -> Left (resolveErr errs)
    Right winners -> do
      ordered <- clausesFrom (byId source <> byId base) (Map.toList winners)
      case gate vocab ordered of
        (f : _) -> Left (RBadClause (faultText "clause" f))
        -- The contracts travel with the core, because the caller needs both and
        -- deriving them twice would let them disagree: what the gate grounded and
        -- what the runtime must provide are the same set by construction.
        []      -> Right ((\t -> ( t
                                 , map cName (reachedContracts vocab ordered)
                                 , [ (clName c, paramCount c) | c <- ordered ] ))
                            <$> renderCore ordered)

-- | The clause set a ground base states, in the program's own line order. Shared
-- by the core assembly and the claim gate, so the two judge the same clauses.
--
-- The @index@ spans the SOURCE base as well as the ground one: a minted clause is
-- derived from the program's decision, and that decision is refined away before
-- realize, so the ground base alone cannot answer which line caused the clause.
clausesFrom :: Map.Map DecisionId Decision -> [(Subject, Decision)]
            -> Either RealizeError [Clause]
clausesFrom index winners = do
  case deepClauseSubjects winners of
    (bad : _) -> Left (RBadClause (bad <> " is not a clause subject: a clause is\
      \ clause.<name>, and a deeper path collapses to the same name as the\
      \ clause it would shadow, which the notation resolves silently."))
    []        -> Right ()
  clauses <- traverse (clauseOf index) (clauseDecisions winners)
  Right (sortOn (locOf . clFrom) clauses)
  where
    -- A clause with no provenance sorts last; the gate rejects it anyway, so the
    -- order only has to be total.
    locOf locs = case locs of
      (SourceLoc _ n : _) -> n
      []                  -> maxBound

-- | The clauses no claim reaches, transitively.
--
-- Behaviour nothing observes is behaviour the next mint may rewrite with no gate
-- noticing, which is the whole reason a clause must be claimed. Requiring merely
-- that SOME claim exists does not get there: a claim naming none of the program's
-- own definitions satisfies that and observes nothing.
--
-- A claim's CALL is the root, because that is what runs. Its expected value is
-- not behaviour, so a clause reachable only from there stays unobserved.
unobservedClauses :: [Clause] -> [ClauseClaim] -> [Text]
unobservedClauses clauses claims =
  [ clName c | c <- clauses, clName c `notElem` reached ]
  where
    reached = close (concatMap (sexpSymbols . ccCall) claims) []
    close [] seen = seen
    close (n : ns) seen
      | n `elem` seen = close ns seen
      | otherwise =
          close (ns <> concatMap (sexpSymbols . clBody) [ c | c <- clauses, clName c == n ])
                (n : seen)

-- | The name the site derivation is built under, for every caller that must
-- write the same binding realize does (the claims file, the compiled flake).
-- 'Nothing' when nothing in the base names the site, so a program without
-- behaviour never mentions a directory compile did not write.
--
-- The head is @site.\<name\>.command@: a site is NAMED, because a program may
-- one day run its behaviour in several places (a browser and a server sharing
-- one clause core) and each place needs its own requirements. Only one site is
-- supported today; two is a loud failure rather than a silent choice, so growing
-- to several is a kernel change nobody can stumble into.
siteNameIn :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
           -> Base -> Either RealizeError (Maybe Text)
siteNameIn modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs -> Left (resolveErr errs)
    Right winners -> do
      let ws = Map.toList winners
          (arts, rest) = partition (rootedAtArtifact . fst) ws
      vals <- traverse (\(sub, d) -> case parseValue (unAssertion (dAssertion d)) of
                          Right v -> Right v
                          Left e  -> Left (RMalformed sub e)) rest
      argSite <- anyArgReferencesSite arts
      siteNameFrom ws (any referencesSite vals || argSite)

-- | The @name@ the site derivation is built under, when anything names the site
-- at all. What the program said to install it as; absent, the derivation is
-- called @site@, which builds and runs but installs under a name no sentence
-- chose.
siteNameFrom :: [(Subject, Decision)] -> Bool -> Either RealizeError (Maybe Text)
siteNameFrom winners referenced
  | not referenced = Right Nothing
  | otherwise = case commands of
      []       -> Right (Just defaultSiteName)
      [(_, d)] -> Just <$> nameOf d
      several  -> Left (RBadClause
        ("this program states " <> T.pack (show (length several))
          <> " sites (" <> T.intercalate ", " (map fst several)
          <> "), and lips builds one. Several places for one clause core is\
             \ physics lips does not have yet."))
  where
    commands = [ (n, d) | (Subject ["site", n, "command"], d) <- winners ]
    -- PARSED, then rendered, like every other value that reaches Nix. Splicing
    -- the assertion text raw put whatever the engine wrote straight into
    -- @name = ...;@, so a value that is not plain text (a list, a package
    -- reference) reached nix as a syntax or type error naming neither lips nor a
    -- remedy.
    nameOf d = case parseValue (unAssertion (dAssertion d)) of
      Right v@(VStr _) -> Right (renderRealized v)
      Right _ -> Left (RBadClause
        ("a site's command must be plain text, because it is the name the\
         \ program is installed under: " <> unAssertion (dAssertion d)))
      Left e -> Left (RMalformed (dSubject d) e)

-- | What the site derivation is called when no sentence chose a name. ONE
-- definition, because the module, the claims file and the compiled flake must
-- all name the same derivation -- and did not: the flake hardcoded @site@ while
-- the module used the program's own name, so @nix run .#site@ built a
-- derivation the module never installs.
defaultSiteName :: Text
defaultSiteName = "\"site\""

-- | The properties this program's site requires, each with the author's reason
-- for it, for the caller that chooses a runtime. Projected from the same base as
-- everything else.
sitePropertiesIn :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                 -> Base -> Either RealizeError [(Text, Text)]
sitePropertiesIn modeOf assemble base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> Right (siteProperties (Map.toList winners))

-- | The properties a site requires, paired with the author's reason for each.
-- What covering selects on beside the contracts the clauses reach, stated by the
-- author because "runs in a browser" or "is one static binary" is intent that
-- lives nowhere else.
--
-- PRESENCE is the requirement: a property is stated by having a decision, so
-- there is no negative form and none is needed (a decision that denied itself
-- would be a contradiction, and the calculus has @Forbid@ for real denials). The
-- assertion is therefore not a value to obey but the REASON, carried into the
-- failure message so an author who states a property nothing offers is told why
-- they wanted it. Nothing is ignored.
siteProperties :: [(Subject, Decision)] -> [(Text, Text)]
siteProperties winners =
  nubBy (\a b -> fst a == fst b)
    [ (p, unAssertion (dAssertion d))
    | (Subject ["site", _, "property", p], d) <- winners ]

-- | Does any artifact ARGUMENT name the site? A wrapper renaming the program is
-- exactly that shape, and its reference needs the same @let@ binding an option
-- value's does.
anyArgReferencesSite :: [(Subject, Decision)] -> Either RealizeError Bool
anyArgReferencesSite arts =
  or <$> traverse one [ sd | sd@(Subject ("artifact" : _ : "args" : _), _) <- arts ]
  where
    one (s, d) = case parseValue (unAssertion (dAssertion d)) of
      Right v -> Right (referencesSite v)
      Left e  -> Left (RMalformed s e)

-- | Does this value name the site, anywhere inside it? A module referencing the
-- site needs the @let@ binding; one that does not must not import a directory
-- compile did not write.
referencesSite :: Value -> Bool
referencesSite (VStr ps)  = any (== PSite) ps
referencesSite (VList vs) = any referencesSite vs
referencesSite (VAttr fs) = any (referencesSite . snd) fs
referencesSite (VRef RSite) = True
referencesSite _          = False

-- | Is this path the clause vocabulary? Twin of 'Lips.Kernel.Claim.claimRooted'
-- and 'Lips.Kernel.OptionType.reservedRoot': no head of it becomes an option.
clauseRooted :: [Text] -> Bool
clauseRooted ("clause" : _) = True
clauseRooted _              = False

-- | Is this path the site vocabulary? @site.name@ tells the module what to call
-- the program's own build; like a clause, it is not an option any world declares.
siteRooted :: [Text] -> Bool
siteRooted ("site" : _) = True
siteRooted _            = False

-- | Every @clause.\<name\>@ decision. The subject is EXACTLY two segments,
-- because a deeper one collapses to the same name: @clause.main.extra@ and
-- @clause.main@ are different subjects, so merge sees no conflict between them,
-- and both would pass the gate as well-formed definitions of @main@ and both
-- would reach the core -- where the notation's last definition silently wins.
clauseDecisions :: [(Subject, Decision)] -> [(Text, Decision)]
clauseDecisions winners = [ (name, d) | (Subject ["clause", name], d) <- winners ]

-- | Clause subjects carrying more than a name. An engine defect, loud: the name
-- such a subject collapses to belongs either to another clause (which it would
-- shadow) or to nobody.
deepClauseSubjects :: [(Subject, Decision)] -> [Text]
deepClauseSubjects winners =
  [ T.intercalate "." segs
  | (Subject segs@("clause" : _), _) <- winners, length segs /= 2 ]

-- | One clause from its decision: the assertion must be an s-expression, and the
-- program lines behind it are walked out of the provenance chain.
clauseOf :: Map.Map DecisionId Decision -> (Text, Decision) -> Either RealizeError Clause
clauseOf index (name, d) = case parseValue (unAssertion (dAssertion d)) of
  Right (VSexp x) -> Right (Clause name x (sourceLocs index d))
  Right _ -> Left (RBadClause ("clause " <> name <> " is not an s-expression: "
                                <> unAssertion (dAssertion d)))
  Left e  -> Left (RBadClause ("clause " <> name <> " does not parse: " <> e))

-- | The program lines a decision rests on, by walking @Derived@ parents back to
-- their sources. A minted clause is always derived (a rule emitted it), so its
-- own provenance names a rule; the LINES are its parents', and they are what a
-- human wrote.
sourceLocs :: Map.Map DecisionId Decision -> Decision -> [SourceLoc]
sourceLocs index = nub . go 8
  where
    go :: Int -> Decision -> [SourceLoc]
    go 0 _ = []                       -- a cycle cannot arise, but never loop on one
    go fuel d = case dProv d of
      FromSource loc  -> [loc]
      Derived ids _   -> concat [ go (fuel - 1) p | i <- ids, Just p <- [Map.lookup i index] ]
      FromGeneration _ -> []

byId :: Base -> Map.Map DecisionId Decision
byId b = Map.fromList [ (dId d, d) | d <- toList b ]

-- | The core file: each definition preceded by the program lines that caused it.
-- Text, because what a runtime consumes is a file; the structure lives in the
-- decisions this is rendered from.
renderCore :: [Clause] -> Maybe Text
renderCore [] = Nothing
renderCore clauses = Just (T.intercalate "\n" (map one clauses))
  where
    one cl = T.concat [ T.concat (map from (clFrom cl))
                      , renderSexp (clBody cl), "\n" ]
    from (SourceLoc f n) = ";; @from " <> f <> ":" <> T.pack (show n) <> "\n"

-- | The clause claims a ground base states: observables over the program's own
-- definitions, judged by evaluating them rather than by running a process.
-- Projected from the same base as the module and the core beside them.
realizeClauseClaims :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
                    -> Vocabulary -> Base -> Base -> Either RealizeError [ClauseClaim]
realizeClauseClaims modeOf assemble vocab source base =
  case resolve modeOf assemble base of
    Left errs     -> Left (resolveErr errs)
    Right winners -> do
      claims  <- either (Left . RBadClaim) Right
                        (clauseClaimsFromDecisions (Map.toList winners))
      clauses <- clausesFrom (byId source <> byId base) (Map.toList winners)
      -- A claim is grounded by the same walk a clause is, with the observations
      -- added: it runs with the core and the adapters loaded, so an ungrounded
      -- name there reaches the world exactly as one in a clause would.
      case concat [ gateClaim vocab clauses (ccId c) [ccCall c, ccEquals c] | c <- claims ] of
        (f : _) -> Left (RBadClause (faultText "claim" f))
        []      -> Right ()
      case unobservedClauses clauses claims of
        [] -> Right claims
        ns -> Left (RBadClause
          ("nothing observes " <> T.intercalate ", " ns <> ": no claim reaches\
           \ those definitions, so the next mint may rewrite them and every gate\
           \ would stay green. State an example whose claim runs them."))

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
      -- A claim and a clause are kernel vocabulary like an artifact: one is
      -- OBSERVED and the other RUN, neither is assigned, so neither may become an
      -- option. Without this a claim would render as `claim.echo.run = "...";`
      -- and a clause as `clause."keep?" = (define ...);` -- paths no target world
      -- declares, carrying text that is not even Nix. The clause case was found
      -- by the first live mint that emitted clauses: every gate passed and the
      -- module then failed to parse.
      opts = [ sd | sd@(Subject segs, _) <- rest
                  , not (claimRooted segs), not (clauseRooted segs)
                  , not (siteRooted segs) ]
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
  -- The site's executable name: what the program said to install it as. Absent,
  -- the derivation is called "site", which builds and runs but installs under a
  -- name no sentence chose.
  -- The site is named from ANY value that mentions it: an option assignment or
  -- an artifact's argument (a wrapper renaming the program is exactly that).
  -- Missing the second is how a live mint produced a module with an undefined
  -- variable, every gate green.
  artSitesRef <- anyArgReferencesSite arts
  let namesSite = any (referencesSite . valOf) optVals || artSitesRef
  if namesSite && not (statesClauses winners)
    then Left (RBadClause
      "a value names ${site}, the program's own behaviour, but the program states\
      \ no clauses for it to build. Either state the behaviour, or name a package\
      \ instead.")
    else Right ()
  siteName <- siteNameFrom winners namesSite
  Right $ T.unlines $
    [ "# lips-realized module. Generated from a ground decision base; do not edit."
    , "{ config, lib, pkgs, ... }:"
    ]
      ++ letBlock siteName entries
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
-- | The module's @let@: the artifact derivations, and the site derivation when
-- the program has behaviour to build. @site@ is bound by importing the runtime's
-- own builder from the directory compile wrote beside this module, so a module
-- can put a program's own behaviour on PATH
-- (@environment.systemPackages = [ site ]@) exactly as it does an artifact.
letBlock :: Maybe Text -> [Text] -> [Text]
letBlock Nothing []      = []
letBlock mSite entries   =
  ["let"] ++ arts ++ site ++ ["in"]
  where
    arts | null entries = []
         | otherwise = ["  artifact = {"] ++ map ("    " <>) entries ++ ["  };"]
    site = case mSite of
      Nothing -> []
      Just nm -> [ "  site = import ./site/build.nix {"
                 , "    inherit pkgs; name = " <> nm <> "; src = ./site;"
                 , "  };" ]

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
