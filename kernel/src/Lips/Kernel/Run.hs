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
  , run
  , runBase
  ) where

import           Data.Bifunctor  (first)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Base
import Lips.Kernel.Decision
import Lips.Kernel.Demand
import Lips.Kernel.Reader   (ParseError, readBase)
import Lips.Kernel.Realize  (RealizeError (..), realize, realizeArtifactFile,
                             realizeStagedPaths)
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

-- | Run a program (canonical-form text) against an engine (its rules and
-- demands). The merge config (derived from the rule emits) and the assembly
-- function are injected, keeping run domain-blind. The budget bounds
-- refinement steps.
run :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
    -> Int -> [Rule] -> [Demand] -> Text -> Either RunError Realization
run modeOf assemble budget rules demands src = do
  base0 <- first ParseRejected (readBase src)
  runBase modeOf assemble budget rules demands base0

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
  , rlArtifact :: Maybe (Text, [Text])
  , rlStaged   :: [(Text, Decision)]
  }

-- | The pipeline from a decision base onward (resolve, demands, refine,
-- realize), shared by canonical @run@ and the loose path where @crystallize@
-- produces the base. Pure in (base, engine). The merge config is injected.
runBase :: (Subject -> MergeMode) -> ([Decision] -> Either Text Decision)
        -> Int -> [Rule] -> [Demand] -> Base -> Either RunError Realization
runBase modeOf assemble budget rules demands base0 = do
  realizable <- runGround budget rules demands (resolve modeOf assemble base0)
  let ground = fromList realizable
  first fromRealizeError $ Realization base0 ground
    <$> realize modeOf assemble ground
    <*> realizeArtifactFile modeOf assemble ground
    <*> realizeStagedPaths modeOf assemble ground

-- | The realizable ground decisions (post resolve, demands, refine, anti-MDA
-- guard). Takes the resolve result
-- so the caller injects the merge config once. A 'Concept' is decorative
-- vocabulary (a heading grouping lines) that carries no obligation to realize
-- and is dropped; a surviving non-'Meta' decision is an unmapped obligation
-- and fails loud (the program escaped the engine), never emitted as garbage.
runGround :: Int -> [Rule] -> [Demand] -> Either [ResolveErr] (Map.Map Subject Decision)
          -> Either RunError [Decision]
runGround budget rules demands resolved = do
  winners <- first toConflicts resolved
  -- Refine the resolved winners, so overridden defaults never realize.
  let base1 = fromList (Map.elems winners)
  case map demQuestion (openQuestions demands base1) of
    []        -> Right ()
    questions -> Left (OpenQuestions questions)
  ground  <- first RefineFailed (refine budget rules base1)
  let realizable = filter ((/= Concept) . dKind) (toList ground)
  case filter ((/= Meta) . dKind) realizable of
    []        -> Right realizable
    leftovers -> Left (Unmapped leftovers)
  where
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
fromRealizeError (RMalformed s e)    = Unrealizable ["option " <> subjText s <> ": " <> e]

-- | Render a subject as a dotted path for a plain-language error.
subjText :: Subject -> Text
subjText (Subject ss) = T.intercalate "." ss
