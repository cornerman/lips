{-# LANGUAGE OverloadedStrings #-}

-- | List aggregation: the Append merge mode's derivation and the assembly of N
-- same-subject list decisions into one (spec: list-aggregation-design,
-- Closure B). The kernel stays domain-blind: it learns only that a subject is a
-- list (because some rule emits a @VList@ rhs to a path that matches it), never
-- what is listed.
--
-- Mode derivation. A subject is 'Append' iff some minted rule emits a 'VList'
-- rhs to a path pattern that matches the subject (capture-aware, so an
-- @attrsOf@-of-list keyed by a capture works too). The option schema is the
-- authority for option types, but it lives only at generate time;
-- 'Lips.Kernel.OptionType.checkEmits' (schema-based) already guarantees a
-- rule's rhs value-shape matches its option type, so the value-shape faithfully
-- reflects the schema at run time and run stays nixpkgs-free. No per-problem
-- kernel branch.
--
-- Assembly. 'assembleSubject' concatenates the top-strength contributors'
-- @VList@ elements in source-line order (human decisions by @(file,line)@
-- before derived by parent line), yielding one synthetic decision whose
-- provenance links every contributor so the chain stays walkable to the metal.
-- Replace-across-strengths is the caller's job (it passes only the
-- top-strength contributors). Order is assembly-only -- never a merge key.
module Lips.Kernel.Engine.Aggregate
  ( MergeMode (..)
  , mergeModeOf
  , assembleSubject
  , assembleWith
  ) where

import           Data.List       (nub, sortOn)
import           Data.Maybe      (isJust)
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Kernel.Base              (MergeMode (..))
import Lips.Kernel.Capture           (matchSubject)
import Lips.Kernel.Decision
import Lips.Kernel.Engine.Data       (Emit (..), MapRule (..))
import Lips.Kernel.Engine.Value      (Value (..), parseValue, renderValue)

-- | A subject is 'Append' iff some rule emits a @VList@ rhs to a path pattern
-- that matches it (capture-aware). Else 'Replace' (today's behavior). The mode
-- is derived from the rule emits, not carried on the decision, so the kernel
-- learns \"this subject is a list\" without learning what it lists.
mergeModeOf :: [MapRule] -> Subject -> MergeMode
mergeModeOf rules (Subject segs)
  | any emitsListHere rules = Append
  | otherwise               = Replace
  where
    emitsListHere r = any emitMatches (mrEmits r)
    emitMatches e = isListRhs (emRhs e) && isJust (matchSubject (emPath e) segs)
    -- A @VTail@ rhs fills to a @VList@ of the program value's tokens, so it is
    -- a list-producing emit just like a literal @VList@ rhs: contributors on
    -- such a subject aggregate (capability C feeding B).
    isListRhs (VList _)   = True
    isListRhs (VTail _ _) = True
    isListRhs _         = False

-- | Assemble one Append subject's top-strength contributors into a single
-- synthetic decision. Each contributor's assertion must be a canonical 'VList'
-- (round-trippable via 'parseValue'/'renderValue' -- the form 'fillValue'
-- stores); elements are concatenated in source-line order. A non-VList
-- contributor is a loud 'Left' (deduce-or-fail: never guess a shape).
assembleSubject :: [Decision] -> Either Text Decision
assembleSubject = assembleWith (const False)

-- | 'assembleSubject' with the per-option aggregation choice injected: given a
-- subject, does that option keep REPEATED elements? A set (the default) collapses
-- them -- two program lines naming one package name it once -- while a list keeps
-- every contribution. The kernel cannot tell which an option is, so the caller
-- passes the engine's own declaration ('Lips.Kernel.Engine.Data.keepsRepeats').
--
-- A clause subject is the exception the kernel answers itself (see below): its
-- contributors are statements, and no engine declaration may drop one.
assembleWith :: ([Text] -> Bool) -> [Decision] -> Either Text Decision
assembleWith _ [] = Left "assembleSubject: no contributors"
assembleWith keepsRepeated contributors = do
  let ordered = sortOn sourceKey contributors
  vals <- traverse listValOf ordered
  let segsOf (Subject ss) = ss
      -- A CLAUSE keeps its repeats whatever the engine declared, and the kernel
      -- decides that rather than the mint: two lines contributing one statement
      -- to a body are two statements, so printing twice is not printing once.
      -- Collapsing them would delete behaviour with every gate still green,
      -- which is the worst failure aggregation can have.
      keeps ss = clauseRooted ss || keepsRepeated ss
      dedup = if keeps (segsOf (dSubject (head' ordered))) then id else nub
      assembled = VList (dedup (concatMap unwrap vals))
      head' (x : _) = x
      head' []      = error "assembleWith: unreachable (empty guarded above)"
      -- 'assembleSubject []' is guarded above, so 'ordered' is non-empty
      -- here; the case keeps it total (no partial 'head').
      smallest = case ordered of
        (x : _) -> x
        []      -> error "assembleSubject: unreachable (empty guarded above)"
  Right Decision
    { dId        = DecisionId (unId (dId smallest) <> "/append")
    , dSubject   = dSubject smallest
    , dKind      = Meta
    , dAssertion = Assertion (renderValue assembled)
    , dStrength  = dStrength smallest
    -- Provenance links every contributor so the chain stays walkable to the
    -- metal. The synthetic RuleId \"append\" names the assembly step (there is
    -- no real rule, but the type is closed).
    , dProv      = Derived (map dId ordered) (RuleId "append")
    , dRationale = Nothing
    }
  where
    unId (DecisionId i) = i
    unwrap (VList vs) = vs
    unwrap _          = []   -- unreachable: listValOf rejects non-VList
    listValOf d = case parseValue (unAssertion (dAssertion d)) of
      Right v@(VList _) -> Right v
      Right _           -> Left ("list subject " <> joinSubj (dSubject d)
                                   <> " got a non-list assertion: " <> unAssertion (dAssertion d))
      Left e            -> Left ("list subject " <> joinSubj (dSubject d) <> ": " <> e)
    joinSubj (Subject ss) = T.intercalate "." ss
    unAssertion (Assertion a) = a

-- | Assembly order: human ('FromSource') before derived ('Derived'), each by
-- their ultimate source line; ties broken by id. Position is NEVER a merge key
-- -- only the assembly rule for Append subjects (spec: ordered assembly).
--
-- The id tie-break is NUMERIC ('naturalKey'), because one line's decisions are
-- numbered @d\<n\>.1@, @d\<n\>.2@, ... and a list hole's items are among them:
-- compared as text, @d9.10@ sorts before @d9.2@, and the eleventh emit of a
-- line would land its item ahead of the second.
sourceKey :: Decision -> (Int, Int, [Either Int Text])
sourceKey d = case dProv d of
  FromSource (SourceLoc _ n)            -> (0, n, naturalKey (unId (dId d)))
  Derived (DecisionId parent : _) _     -> (1, parentLine parent, naturalKey (unId (dId d)))
  _                                     -> (2, 0, naturalKey (unId (dId d)))
  where
    unId (DecisionId i) = i
    -- The standard id scheme is d<n> (or d<n>.k for a dense line); a derived
    -- Meta decision's parent is a human d<n>, so its line orders it here.
    parentLine p = case T.stripPrefix "d" p of
      Just rest -> case TR.decimal (T.takeWhile isDigit rest) of
        Right (n, _) -> n
        Left _       -> 0
      Nothing  -> 0
    isDigit c = c >= '0' && c <= '9'

-- | An id cut into its digit runs (compared as numbers) and the text between
-- them, so @d9.2@ < @d9.10@ and @d9.2/r1#1@ < @d9.10/r1#1@. Ids share one
-- scheme, so two keys line up run against run; where they do not, 'Either''s
-- own order still gives a total, deterministic one.
naturalKey :: Text -> [Either Int Text]
naturalKey t
  | T.null t  = []
  | otherwise = case T.span isDigit t of
      ("", _)      -> let (txt, rest) = T.break isDigit t in Right txt : naturalKey rest
      (digits, rest) -> case TR.decimal digits of
        Right (n, _) -> Left n : naturalKey rest
        Left _       -> Right digits : naturalKey rest   -- unreachable: all digits
  where
    isDigit c = c >= '0' && c <= '9'
