{-# LANGUAGE OverloadedStrings #-}

-- | @run@: the whole deterministic pipeline, no AI (spec v2, section 5). It
-- reads a program in canonical form, resolves it, checks its demands, refines
-- it with a language's rules, and realizes the result to a NixOS module.
--
-- 'RunError' is exactly the spec's four run outcomes: a parse rejection (a line
-- no pattern reads), an open question (an unmet demand), a conflict
-- (equal-strength contradiction), or a refinement failure. Success is the
-- realized module. Only minting new rules needs a model; everything here is a
-- pure function of (program, engine).
module Lips.Kernel.Run
  ( RunError (..)
  , Realization (..)
  , composeWith
  , lentNames
  , usesIn
  , run
  , runBase
  ) where

import           Data.Bifunctor  (first)
import           Data.List       (nub)
import           Data.Maybe      (isJust, mapMaybe)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader   (ParseError, readBase)
import Lips.Kernel.Claim    (Claim, ClauseClaim)
import Lips.Kernel.Clause.Vocabulary (Vocabulary)
import Lips.Kernel.Realize  (RealizeError (..), realize, realizeArtifactFile, realizeClauseClaims,
                             realizeClauses, siteNameIn, sitePropertiesIn,
                             realizeArtifactFills, realizeArtifactPaths,
                             realizeClaims, realizeStagedPaths)
import Lips.Kernel.Capture  (matchSubject)
import Lips.Kernel.Engine.Data (Engine (..), IgnoreSpec (..))
import Lips.Kernel.Refine

-- | The four run outcomes other than success (spec section 5).
data RunError
  = -- | A line no pattern reads. The only outcome that re-enters @generate@.
    ParseRejected [ParseError]
  | -- | Unmet demands, surfaced verbatim; answered by adding lines, no AI.
    OpenQuestions [Text]
  | -- | An equal-strength contradiction, both provenances cited.
    Conflicted [Conflict]
  | -- | A refinement failure: rule overlap or non-termination.
    RefineFailed RefineError
  | -- | Ground decisions no rule mapped to a mechanism: the program escaped the
    -- engine (spec section 3, the anti-MDA guard). Never realized as a guess;
    -- re-enters generate so the engine grows a mapping.
    Unmapped [Decision]
  | -- | Realization refused a ground base for an engine defect (a dangling
    -- @${artifact}@ reference or a malformed artifact group), each reason in
    -- plain words. A conflict is reported as 'Conflicted', not here.
    Unrealizable [Text]
  deriving (Eq, Show)

-- | Run a program (canonical-form text) against an 'Engine' (its rules, demands
-- and the facts it declares it cannot place). The merge config (derived from the rule emits) and the assembly
-- function are injected, keeping run domain-blind. The budget bounds
-- refinement steps.
run :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
    -> Vocabulary -> Int -> Engine -> Text
    -> Either RunError Realization
run modeOf assemble vocab budget eng src = do
  base0 <- first ParseRejected (readBase src)
  runBase modeOf assemble vocab budget eng base0

-- | Everything the pipeline projects from ONE ground base: the module, the
-- buildable artifacts (or 'Nothing' when the program declares none), and the
-- relative paths the output names (which the caller checks against the tree it
-- stages). One record, because they must agree: the artifacts a compiled flake
-- addresses are byte-for-byte the ones the module @let@-binds, and the staged
-- paths are exactly the ones both contain. Three separate entry points ran the
-- whole pipeline three times to answer three questions about one run.
-- The base it was projected FROM travels with them, so a caller that judges
-- the output against the program (the behavioral contract) cannot pair a module
-- with someone else's base. So does the GROUND base it was projected from: an
-- artifact arg is not an attribute of the module, so a contract on one is judged
-- against these decisions (see 'Lips.Kernel.Expect.checkArtifactValues').
data Realization = Realization
  { rlBase     :: Base
  , rlGround   :: Base
  , rlModule   :: Text
  , rlArtifact :: (Text, [Text])
    -- ^ The @artifact.nix@ body and the artifact names it binds. Always a body,
    -- empty set when the program declares none, so every writer emits the file
    -- unconditionally and the names list alone says whether there is anything
    -- to build.
  , rlStaged   :: [(Text, Decision)]
  , rlArtPaths :: [(Text, Text, Decision)]
    -- ^ @(artifact, \/rel\/path, the decision that named it)@: what the output
    -- expects to find INSIDE a build. Only building the artifact answers it,
    -- so the caller that owns nix does, exactly as it checks 'rlStaged' against
    -- the tree it stages.
  , rlFills    :: [(Text, Text, Text)]
    -- ^ @(artifact, marker, text)@: what the caller substitutes into the source
    -- tree it stages, so a program word reaches inside the compiled program.
  , rlCore     :: Maybe (Text, [Text], [(Text, Maybe Int)])
    -- ^ The clause core, the contracts it reaches, and what it defines with how
    -- many parameters -- 'Nothing' for a constant, which is not a procedure of no
    -- arguments (so a caller can check the core satisfies its runtime's
    -- entry). One Scheme file assembled from the @clause.\<name\>@
    -- decisions, gated, each definition naming the program lines behind it.
    -- 'Nothing' for a program that states no behaviour, which is every
    -- configuration-only program.
  , rlSiteProps :: [(Text, Text)]
    -- ^ The properties this program's site requires ("browser", "static-binary"),
    -- each with the author's reason for it. Covering selects on these beside the
    -- contracts the clauses reach, so which runtime runs the behaviour is a
    -- computation over requirements rather than anyone's choice.
  , rlSiteName :: Maybe Text
    -- ^ What to call the site derivation, when anything names it. Carried so
    -- every caller that must write the same binding realize does (the claims
    -- file, the compiled flake) agrees with the module by construction.
  , rlClauseClaims :: [ClauseClaim]
    -- ^ The observables over the program's own definitions, judged offline.
    -- Projected from the same ground base as the core they observe, so what
    -- @check@ judges and what @compile@ writes cannot disagree.
  , rlClaims   :: [Claim]
    -- ^ The observables the program states, empty for a program that states
    -- none. Projected from the same ground base as the module beside them, so
    -- what @check@ runs and what the module contains cannot disagree.
  , rlUses     :: [(Text, Text)]
    -- ^ @(language, instance)@: the other programs this one composes with, from
    -- its 'Uses' decisions. Realizing nothing itself, a dependency names a base
    -- to union with this one, so the site assembler consumes it and the run only
    -- carries it -- which is why it is neither realized nor reported unmapped.
  }

-- | The pipeline from a decision base onward (resolve, demands, refine,
-- realize), shared by canonical @run@ and the loose path where @crystallize@
-- produces the base. Pure in (base, engine). The merge config is injected.
-- The clause vocabulary is injected for the same reason the merge config is:
-- what grounds a name in a clause is data a tier above lips ships, and the
-- kernel stays a reader of it.
runBase :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
        -> Vocabulary -> Int -> Engine -> Base
        -> Either RunError Realization
runBase modeOf assemble vocab budget eng base0 = do
  realizable <- runGround budget eng (resolve modeOf assemble base0)
  let ground = fromList realizable
  first fromRealizeError $ Realization base0 ground
    <$> realize modeOf assemble ground
    <*> realizeArtifactFile modeOf assemble ground
    <*> realizeStagedPaths modeOf assemble ground
    <*> realizeArtifactPaths modeOf assemble ground
    <*> realizeArtifactFills modeOf assemble ground
    <*> realizeClauses modeOf assemble vocab base0 ground
    <*> sitePropertiesIn modeOf assemble ground
    <*> siteNameIn modeOf assemble ground
    <*> realizeClauseClaims modeOf assemble vocab base0 ground
    <*> realizeClaims modeOf assemble ground
    <*> pure (usesIn base0)

-- | Compose a realization with the ones it depends on: their clause cores are
-- linked ahead of its own, so a call into an imported definition resolves at
-- link time by NAME, which is all a first-order clause world needs.
--
-- Only the core travels. A dependency lends its behaviour, never its module: an
-- imported program's options, artifacts and claims stay its own, or importing a
-- language would silently deploy it. Namespacing makes the union safe by
-- construction, since two languages cannot name one clause.
composeWith :: [Realization] -> Realization -> Realization
composeWith imports rl = rl { rlCore = merged }
  where
    merged = case (mapMaybe rlCore imports, rlCore rl) of
      ([], own)     -> own
      (cs, Nothing) -> Just (foldCores cs)
      (cs, Just own) -> Just (foldCores (cs <> [own]))
    foldCores cs =
      ( T.intercalate "\n" [ t | (t, _, _) <- cs ]
      , nub (concat [ cts | (_, cts, _) <- cs ])
      , concat [ ds | (_, _, ds) <- cs ] )

-- | What imported realizations lend their importer: every name their cores
-- define. Fed to 'Lips.Kernel.Clause.Vocabulary.withLent' before the importer's
-- own run, since a call is grounded during realization and composed after it.
lentNames :: [Realization] -> [Text]
lentNames rs = [ n | r <- rs, Just (_, _, ds) <- [rlCore r], (n, _) <- ds ]

-- | The dependencies a base states: @(language, instance)@ per 'Uses' decision,
-- read from the human base, since no rule rewrites one and none may.
usesIn :: Base -> [(Text, Text)]
usesIn b = [ (T.intercalate "." segs, a)
           | d <- toList b, dKind d == Uses
           , let Subject segs = dSubject d, let Assertion a = dAssertion d ]

-- | The realizable ground decisions (post resolve, demands, refine, anti-MDA
-- guard). Takes the resolve result
-- so the caller injects the merge config once. A 'Concept' is decorative
-- vocabulary (a heading grouping lines) that carries no obligation to realize
-- and is dropped; a surviving non-'Meta' decision is an unmapped obligation
-- and fails loud (the program escaped the engine), never emitted as garbage.
runGround :: Int -> Engine
          -> Either [ResolveErr] (Map.Map Subject Decision)
          -> Either RunError [Decision]
runGround budget eng resolved = do
  winners <- first toConflicts resolved
  -- Refine the resolved winners, so overridden defaults never realize.
  let base1 = fromList (Map.elems winners)
  case map demQuestion (openQuestions (enDemands eng) base1) of
    []        -> Right ()
    questions -> Left (OpenQuestions questions)
  ground  <- first RefineFailed (refine budget (enRules eng) base1)
  -- Two ways a decision may reach no option and still be sound. A CONCEPT
  -- realizes nothing anywhere, by definition. An IGNORED decision is a fact this
  -- lowering has no place for, declared with its reason in this world's own
  -- rules; another world of the language places it (the shell checks that, since
  -- one engine cannot see the others). Both are dropped rather than realized:
  -- neither names an option to fill.
  let ignored d = any (covers d) (enIgnores eng)
      covers d ig = igKind ig == dKind d
                      && isJust (matchSubject (igSubject ig) (segsOf (dSubject d)))
      segsOf (Subject segs) = segs
      -- Three ways a decision reaches no option soundly. A CONCEPT is
      -- decorative vocabulary. An IGNORED decision is a fact this world declares
      -- it cannot place. A USES decision names another program to compose with,
      -- which the site assembler consumes and no rule ever places.
      realizable = filter (\d -> dKind d `notElem` [Concept, Uses] && not (ignored d))
                          (toList ground)
  case filter (not . mechanism) realizable of
    []        -> Right realizable
    leftovers -> Left (Unmapped leftovers)
  where
    -- What a rule placed: a mapped mechanism, or glue a rule emitted into a
    -- builder's argument. Glue counts only when DERIVED: a program decision of
    -- kind glue that no rule maps is an obligation the engine never met.
    mechanism d = case (dKind d, dProv d) of
      (Meta, _)          -> True
      (Glue, Derived {}) -> True
      _                  -> False
    -- Resolve groups by subject; a subject is either Replace (a conflict) or
    -- Append (an assembly defect). Conflicts are the author's to edit; an
    -- assembly failure on the human base is an engine defect surfaced as
    -- Unrealizable so it is never silent (invariant 2). For a valid engine the
    -- Append branch is unreachable at the human base (a list emit's rhs fills
    -- to a VList, so assembly never fails), but a buggy engine must still fail
    -- loud, not as an empty Conflicted.
    toConflicts errs =
      case [ c | REConflict c <- errs ] of
        cs@(_ : _) -> Conflicted cs
        []         -> Unrealizable
          [ "list " <> subjText s <> ": " <> e | REAssemble s e <- errs ]

-- | Map a realization defect to its run outcome. A dangling @${artifact}@ or a
-- malformed group is an engine bug (Unrealizable); an equal-strength
-- contradiction is Conflicted.
fromRealizeError :: RealizeError -> RunError
fromRealizeError (RConflicts cs)     = Conflicted cs
fromRealizeError (RDangling ns)      = Unrealizable
  ["references artifact(s) nothing builds: " <> T.intercalate ", " ns]
fromRealizeError (RBadArtifact n why) = Unrealizable ["artifact " <> n <> ": " <> why]
fromRealizeError (RBadClaim why)     = Unrealizable [why]
-- A clause that fails the subset gate is an engine bug like the others: the
-- program is fine, the mint reached for something it may not name.
fromRealizeError (RBadClause why)    = Unrealizable [why]
fromRealizeError (RMalformed s e)    = Unrealizable ["option " <> subjText s <> ": " <> e]

-- | Render a subject as a dotted path for a plain-language error.
subjText :: Subject -> Text
subjText (Subject ss) = T.intercalate "." ss
