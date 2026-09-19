{-# LANGUAGE OverloadedStrings #-}

-- | Static orthogonality: do two minted rules claim the same decision?
--
-- 'Lips.Kernel.Refine' already answers this dynamically -- a decision matched
-- by several rules is an 'Lips.Kernel.Refine.Overlap' error -- but only for an
-- overlap some concrete decision witnesses. Two rules whose subjects are
-- @route.\<path\>.status@ and @route.\<name\>.status@ are indistinguishable
-- for every route that could ever exist, yet a program stating no route at all
-- refines clean and the defect ships inside the engine. It then surfaces on
-- the author's machine, at compile time, in a program that did nothing wrong.
--
-- So the check belongs at the mint gate, where an engine is still rejectable,
-- and it must be static: not "did any decision hit both rules" but "could
-- any". That is the classical critical-pair question of term rewriting -- a
-- rewrite system that is non-overlapping is confluent (Rosen, /Tree-Manipulating
-- Systems and Church-Rosser Theorems/, JACM 1973) -- specialized to the shape
-- lips actually has: a rule's left-hand side is a flat, fixed-length subject
-- pattern over literals and @\<name\>@ captures, plus a kind. Two left-hand
-- sides overlap exactly when they unify.
--
-- Unification, not a position-by-position comparison, because a repeated
-- capture constrains: @x.\<a\>.\<a\>@ matches only subjects whose last two
-- segments are equal, so it does NOT overlap @x.p.q@. A positionwise check
-- would call that an overlap and reject a legitimate engine -- a false
-- rejection is as bad as a missed defect, since the mint gate must let every
-- sound engine through (deduce-or-fail cuts both ways).
--
-- The witness is the unified subject family: the most general subject both
-- rules claim, rendered with any still-open capture left as @\<name\>@. It
-- names what is actually ambiguous, which is what the model needs to fix the
-- rule it wrote.
module Lips.Kernel.Engine.Overlap
  ( RuleOverlap (..)
  , ruleOverlaps
  , subjectsUnify
  , renderRuleOverlap
  , PatternOverlap (..)
  , patternOverlaps
  , renderPatternOverlap
  ) where

import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe      (isJust)
import           Data.Text       (Text)

import qualified Data.Set        as Set
import qualified Data.Text       as T

import Lips.Kernel.Capture      (captureName)
import Lips.Kernel.Engine.Data  (MapRule (..), renderAttrPath)
import Lips.Kernel.Lang.Pattern (FusedSeg (..), Pattern (..), TplTok (..), fusedHoles)

-- | Two rules that could claim one decision, with the subject family that
-- witnesses it (still-open captures rendered as @\<name\>@).
data RuleOverlap = RuleOverlap
  { roLeft    :: Text
  , roRight   :: Text
  , roWitness :: [Text]
  }
  deriving (Eq, Show)

-- | Every overlapping pair of rules, each pair once, in rule order. Empty
-- means the rule set is orthogonal, hence its refinement is a function.
ruleOverlaps :: [MapRule] -> [RuleOverlap]
ruleOverlaps rules =
  [ o
  | (l : rest) <- tails' rules
  , r <- rest
  , Just o <- [overlapOf l r]
  ]
  where
    tails' []       = []
    tails' t@(_:xs) = t : tails' xs

-- | Do these two rules overlap? Kind first (the refiner matches kind before
-- subject), then unification of the two subject patterns.
overlapOf :: MapRule -> MapRule -> Maybe RuleOverlap
overlapOf l r
  | mrKind l /= mrKind r = Nothing
  | otherwise = do
      let lhs = terms "l" (mrSubject l)
          rhs = terms "r" (mrSubject r)
      subst <- unify lhs rhs
      pure (RuleOverlap (mrId l) (mrId r) (map (render . resolve subst) lhs))

-- | Could one concrete subject match both of these subject patterns? The
-- yes/no half of 'overlapOf', without the witness -- shared so the
-- dropped-value check ('Lips.Kernel.Engine.Reach') asks the SAME question about
-- a pattern's emitted subject family and a rule's left-hand side. Two copies of
-- unification would be two places for the answer to drift.
subjectsUnify :: [Text] -> [Text] -> Bool
subjectsUnify l r = isJust (unify (terms "l" l) (terms "r" r))

-- | A subject segment is either a literal or a capture variable. Variables are
-- tagged by side, so the two rules' capture names cannot collide: @\<path\>@ in
-- one rule and @\<path\>@ in the other are independent.
data Term = Lit Text | Var Text Text
  deriving (Eq, Show)

terms :: Text -> [Text] -> [Term]
terms side = map term
  where
    term s = maybe (Lit s) (Var side) (captureName s)

-- | Unify two flat, equal-length term lists. No occurs check is needed: terms
-- have no structure, so a variable can only ever bind to a literal or another
-- variable and no cycle can form.
unify :: [Term] -> [Term] -> Maybe (Map Text Term)
unify as bs
  | length as /= length bs = Nothing
  | otherwise              = foldl step (Just Map.empty) (zip as bs)
  where
    step Nothing _ = Nothing
    step (Just s) (a, b) = case (resolve s a, resolve s b) of
      (Lit x, Lit y)
        | x == y                -> Just s
        | otherwise             -> Nothing
      -- Two captures: bind the right one to the left, so the witness (which
      -- resolves the LEFT rule's segments) reports the family under the name
      -- the first-named rule gave it.
      (Var ls lv, Var rs rv)
        | key ls lv == key rs rv -> Just s
        | otherwise              -> Just (Map.insert (key rs rv) (Var ls lv) s)
      (Var side v, t)           -> Just (Map.insert (key side v) t s)
      (t, Var side w)           -> Just (Map.insert (key side w) t s)

-- | Follow a variable's binding chain to the term that actually stands there.
resolve :: Map Text Term -> Term -> Term
resolve s t@(Var side v) = maybe t (resolve s) (Map.lookup (key side v) s)
resolve _ t              = t

key :: Text -> Text -> Text
key side v = side <> ":" <> v

-- | A witness segment: a literal as itself, an unbound capture as @\<name\>@.
render :: Term -> Text
render (Lit t)    = t
render (Var _ v)  = "<" <> v <> ">"

-- | One overlap in the words a rule author (the model, at the mint gate) needs:
-- which two rules, and the subject family they both claim.
renderRuleOverlap :: RuleOverlap -> Text
renderRuleOverlap o =
  "rules " <> roLeft o <> " and " <> roRight o
    <> " both match " <> renderAttrPath (roWitness o)

-- | Two patterns whose templates could read one line, with the line shape that
-- witnesses it (a hole's own name stands where any word fits).
data PatternOverlap = PatternOverlap
  { poLeft    :: Text
  , poRight   :: Text
  , poWitness :: [Text]
  }
  deriving (Eq, Show)

-- | Every overlapping pair of patterns, each pair once, in pattern order. The
-- pattern-layer sibling of 'ruleOverlaps', and the same argument: 'crystallize'
-- reports 'Lips.Kernel.Lang.Crystallize.Overlapping' only for an overlap some
-- line in the corpus happens to witness, so a language can ship two templates no
-- example separates and fail later on the author's own program.
--
-- A template is a token sequence over three forms (a literal, a one-token hole,
-- a multi-token hole), which makes "could one line match both" the emptiness of
-- an intersection: a product walk over the two templates, one token at a time,
-- where a multi-token hole may stay or advance. Exact, no heuristic, and the
-- first path that reaches both ends is the witness.
--
-- One case is deliberately SKIPPED rather than approximated: a template that
-- repeats a hole name (@\<a\> ... \<a\>@) constrains the two positions to the
-- same word, which the product walk does not track, so calling it an overlap
-- could reject a sound engine. A false rejection is as bad as a missed defect
-- (deduce-or-fail cuts both ways), and the dynamic check still covers it.
patternOverlaps :: [Pattern] -> [PatternOverlap]
patternOverlaps pats =
  [ PatternOverlap (pId l) (pId r) w
  | (l : rest) <- tails' pats
  , r <- rest
  , not (repeatsHole l), not (repeatsHole r)
  , Just w <- [templatesOverlap (pTemplate l) (pTemplate r)]
  ]
  where
    tails' []       = []
    tails' t@(_:xs) = t : tails' xs
    repeatsHole p = let hs = [ h | tok <- pTemplate p, h <- holeName tok ]
                     in length hs /= length (Set.toList (Set.fromList hs))
    holeName (THole h)   = [h]
    holeName (TMulti h)  = [h]
    holeName (TList h _) = [h]
    holeName (TFused seg) = fusedHoles seg
    holeName (TLit _)    = []

-- | Could one token sequence match both templates? 'Just' the shortest witness
-- the walk finds, 'Nothing' when the two templates read disjoint line shapes.
templatesOverlap :: [TplTok] -> [TplTok] -> Maybe [Text]
templatesOverlap l r = go Set.empty (l, r)
  where
    go seen (as, bs)
      | st' `Set.member` seen = Nothing
      | otherwise = case (as, bs) of
          ([], [])  -> Just []
          -- Every token form consumes at least one word, so a leftover template
          -- can never match an exhausted line.
          ([], _)   -> Nothing
          (_, [])   -> Nothing
          (a : as', b : bs') -> case step a b of
            Nothing      -> Nothing
            Just (w, ks) -> firstJust [ (w :) <$> go (Set.insert st' seen) (pick a as as' ka, pick b bs bs' kb)
                                      | (ka, kb) <- ks ]
      where st' = (length as, length bs)
    -- One word, consumed by both sides at once, plus how each side may continue:
    -- 'Stay' is a multi-token hole taking another word, 'Next' moves on.
    -- A list hole reads a run of words exactly as a multi-token hole does; the
    -- cut into items only narrows what it accepts, so the walk asks its
    -- question over the wider form and never misses an overlap.
    step (TList h _) b = step (TMulti h) b
    step a (TList h _) = step a (TMulti h)
    step (TLit x) (TLit y) | x /= y = Nothing
                           | otherwise = Just (x, [(Next, Next)])
    step (TLit x) (THole _)  = Just (x, [(Next, Next)])
    step (THole _) (TLit y)  = Just (y, [(Next, Next)])
    step (THole h) (THole _) = Just (word h, [(Next, Next)])
    step (TLit x) (TMulti _) = Just (x, [(Next, Stay), (Next, Next)])
    step (TMulti _) (TLit y) = Just (y, [(Stay, Next), (Next, Next)])
    step (THole h) (TMulti _) = Just (word h, [(Next, Stay), (Next, Next)])
    step (TMulti h) (THole _) = Just (word h, [(Stay, Next), (Next, Next)])
    step (TMulti h) (TMulti _) =
      Just (word h, [(Stay, Stay), (Stay, Next), (Next, Stay), (Next, Next)])
    -- A fused token reads ONE word, so it meets the other forms as a hole does;
    -- against another fused token the question is whether one word satisfies
    -- both, which 'fusedMeet' answers exactly, the same product walk one level
    -- down (characters instead of words).
    step (TFused g) (TFused g') = (\w -> (w, [(Next, Next)])) <$> fusedMeet g g'
    step (TFused g) (TLit y)   = (\w -> (w, [(Next, Next)])) <$> fusedMeet g [FLit y]
    step (TLit x) (TFused g')  = (\w -> (w, [(Next, Next)])) <$> fusedMeet [FLit x] g'
    step (TFused g) (THole _)  = Just (renderFused g, [(Next, Next)])
    step (THole _) (TFused g') = Just (renderFused g', [(Next, Next)])
    step (TFused g) (TMulti _) = Just (renderFused g, [(Next, Stay), (Next, Next)])
    step (TMulti _) (TFused g') = Just (renderFused g', [(Stay, Next), (Next, Next)])
    pick _ whole _    Stay = whole
    pick _ _     rest Next = rest
    word h = "<" <> h <> ">"
    firstJust xs = case [ x | Just x <- xs ] of
      (x : _) -> Just x
      []      -> Nothing

-- | How a side continues after consuming one word.
data Step = Stay | Next

-- | Could ONE token satisfy both fused templates? 'Just' a witness word, or
-- 'Nothing' when their literal pieces cannot line up. The walk consumes one
-- CHARACTER at a time from each side; a hole may keep the character (staying
-- open) or end on it, exactly as a multi-token hole may stay or advance.
fusedMeet :: [FusedSeg] -> [FusedSeg] -> Maybe Text
fusedMeet l r = go Set.empty (norm l, norm r)
  where
    -- An exhausted literal piece is no piece at all.
    norm (FLit t : ss) | T.null t = norm ss
    norm ss = ss
    go seen st@(as, bs)
      | st `Set.member` seen = Nothing
      | otherwise = case (as, bs) of
          ([], [])  -> Just ""
          ([], _)   -> Nothing   -- a piece still to match, nothing left to match it
          (_, [])   -> Nothing
          (a : as', b : bs') -> case chars a b of
            Nothing      -> Nothing
            Just (c, ks) -> firstJust
              [ T.cons c <$> go (Set.insert st seen) (norm (pick a as' ka), norm (pick b bs' kb))
              | (ka, kb) <- ks ]
      where
        -- A literal piece keeps its remaining characters; a hole either stays
        -- open or ends here.
        pick (FLit t) rest _    = FLit (T.drop 1 t) : rest
        pick (FHole h) rest Stay = FHole h : rest
        pick (FHole _) rest Next = rest
    -- The one character both sides consume, plus how each may continue.
    chars (FLit x) (FLit y)
      | T.head x == T.head y = Just (T.head x, [(Next, Next)])
      | otherwise            = Nothing
    chars (FLit x) (FHole _) = Just (T.head x, [(Next, Stay), (Next, Next)])
    chars (FHole _) (FLit y) = Just (T.head y, [(Stay, Next), (Next, Next)])
    chars (FHole _) (FHole _) =
      Just ('x', [(Stay, Stay), (Stay, Next), (Next, Stay), (Next, Next)])
    firstJust xs = case [x | Just x <- xs] of
      (x : _) -> Just x
      []      -> Nothing

-- | A fused template as the line shape a reader sees: its literal pieces with
-- each hole spelled by name.
renderFused :: [FusedSeg] -> Text
renderFused = T.concat . map seg
  where
    seg (FLit t)  = t
    seg (FHole h) = "<" <> h <> ">"

-- | One overlap in the words the mint needs: which two patterns, and a line
-- shape they both read.
renderPatternOverlap :: PatternOverlap -> Text
renderPatternOverlap o =
  "patterns " <> poLeft o <> " and " <> poRight o
    <> " both read the line " <> T.unwords (poWitness o)
