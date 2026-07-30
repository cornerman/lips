{-# LANGUAGE OverloadedStrings #-}

-- | Blocks: how a program line sees the block it sits in.
--
-- A block is a line plus the lines that scope to it. Nothing about a block is
-- spelled in the kernel: no indentation rule, no bullet, no colon, no header
-- token. The kernel would otherwise be dictating a collection syntax, and which
-- words open a block is exactly the per-problem knowledge that belongs in the
-- minted engine. So the language's own words mark it, through patterns:
--
--   * an engine declares that one PATTERN nests under another
--     ('Lips.Kernel.Lang.Pattern.pParent', spelled @p3.under.p2@);
--   * a matching line is then read as an item of the block headed by the
--     NEAREST PRECEDING line that matched that parent pattern;
--   * the parent's captures are in scope in the child, so a child's emitted
--     subject can carry the word the header stated
--     (@fact host.\<domain\>.route.\<path\>.proxy@).
--
-- What this buys, from the three programs that drove it: two @host@ blocks each
-- with a @\/@ location no longer collide on one subject (they did, and lips told
-- the author to delete one of two correct lines); an anonymous record keeps its
-- fields together; and an item with no key of its own gets one from
-- @\<n:index\>@, its position among its siblings.
--
-- Nothing else moves. The decision atom, merge, refinement, realization and the
-- canonical @.decisions@ text are untouched: a block is a scope at
-- crystallize time, not a new decision shape. In particular no decision \"owns\"
-- a list -- @Append@ ('Lips.Kernel.Engine.Aggregate') already assembles one
-- from N same-option contributors in source order.
--
-- Indentation carries meaning in exactly one place: a pattern nested under
-- ITSELF (@p3.under.p3@), where nothing else could say how deep a line sits.
-- Everywhere else leading whitespace stays what it has always been, free
-- decoration.
module Lips.Kernel.Lang.Nest
  ( NestError (..)
  , renderNestError
  , checkNesting
  , ancestorsOf
  , holesInScope
  , Frame (..)
  , Frames
  , noFrames
  , scopeLine
  ) where

import           Data.List       (find, nub, sort)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Lang.Pattern (Pattern (..), PatEmit (..), StrPart (..),
                                 StructType (..), holesOf, refName, structHoles)

-- | An engine whose nesting does not close. Every case is refused at the one
-- door that reads a @.lang@ ('Lips.Kernel.Lang.Store.readLang'), so @generate@,
-- @compile@, @check@ and @lsp@ all inherit it.
data NestError
  = -- | A pattern nests under an id no pattern defines.
    UnknownParent Text Text
  | -- | A nesting cycle: no line could ever be scoped. A pattern under ITSELF is
    -- not one (that is legal unbounded depth); this is a cycle through two or
    -- more patterns.
    NestCycle [Text]
  | -- | Emit holes bound by neither this pattern nor any ancestor, so
    -- 'Lips.Kernel.Lang.Pattern.applyPattern' could not fill them.
    UnboundInScope Text [Text]
  deriving (Eq, Show)

-- | One nesting failure in the words its author (the model, at the mint gate)
-- needs: what is wrong, and which pattern to fix.
renderNestError :: NestError -> Text
renderNestError (UnknownParent p q) =
  "pattern " <> p <> " nests under " <> q <> ", which no pattern defines"
renderNestError (NestCycle ids) =
  "patterns " <> T.intercalate " -> " ids <> " nest in a cycle, so no line could be read"
renderNestError (UnboundInScope p hs) =
  "pattern " <> p <> " emits <" <> T.intercalate ">, <" hs
    <> ">, which neither it nor the block it sits in binds"

-- | The patterns enclosing this one, nearest first, excluding itself. Total on
-- any engine: it stops at a missing parent and at a repeat, so a malformed
-- engine yields a short list rather than a loop ('checkNesting' is what refuses
-- it).
ancestorsOf :: [Pattern] -> Pattern -> [Pattern]
ancestorsOf pats p = go (pParent p) [pId p]
  where
    go Nothing _ = []
    go (Just q) seen
      | q `elem` seen = []
      | otherwise = case find ((== q) . pId) pats of
          Nothing -> []
          Just a  -> a : go (pParent a) (q : seen)

-- | Every hole name a pattern may reference: the ones its own template binds,
-- the structure-bound ones it declares, and the same two for every ancestor.
-- This is the set 'applyPattern' will find filled, so the static gates
-- ('Lips.Kernel.Engine.Reach', 'Lips.Kernel.Engine.Answerable') build their
-- marker bindings from it rather than from the template alone.
holesInScope :: [Pattern] -> Pattern -> [Text]
holesInScope pats p = nub (concatMap own (p : ancestorsOf pats p))
  where own a = holesOf a ++ map fst (structHoles a)

-- | Every way an engine's nesting fails to close, in pattern-id order so the
-- report is deterministic. Empty means every child has a parent, no cycle
-- exists, and every emit hole is bound by the pattern or its block.
checkNesting :: [Pattern] -> [NestError]
checkNesting pats =
  [ e | p <- sortById pats, e <- unknown p ]
    ++ cycles
    ++ [ e | p <- sortById pats, e <- unbound p ]
  where
    sortById = map snd . Map.toAscList . Map.fromList . map (\p -> (pId p, p))
    known q = any ((== q) . pId) pats
    unknown p = [UnknownParent (pId p) q | Just q <- [pParent p], not (known q)]
    cycles = map NestCycle (nub (sort (concatMap cycleAt (sortById pats))))
    -- Only a hole the emits actually reference matters; an ancestor may bind
    -- names this pattern never uses.
    unbound p =
      let scope = holesInScope pats p
          used  = nub [ refName h
                      | e <- pEmits p
                      , SHole h <- peSubject e ++ peAssertion e ]
          loose = filter (`notElem` scope) used
       in [UnboundInScope (pId p) loose | not (null loose)]
    -- Walk the parent chain from p. Coming back to the pattern just visited is
    -- self-nesting (legal); coming back to an earlier one is a cycle, reported
    -- rotated to its smallest id so both members report the same one.
    cycleAt p = go (pParent p) [pId p]
      where
        go Nothing _ = []
        go (Just q) seen
          | Just q == lastOf seen = []
          | q `elem` seen         = [rotate (dropUntil q seen)]
          | otherwise = case find ((== q) . pId) pats of
              Nothing -> []
              Just a  -> go (pParent a) (seen ++ [q])
    lastOf xs = if null xs then Nothing else Just (last xs)
    dropUntil q = dropWhile (/= q)
    rotate ids = case sort ids of
      (m : _) -> dropUntil m ids ++ takeWhile (/= m) ids
      []      -> ids

-- | What crystallize remembers about one matched line so later lines can scope
-- to it: where it was, how deep, which line heads its own block, and the
-- bindings visible inside it.
data Frame = Frame
  { frLine   :: Int
  , frIndent :: Int
  , frParent :: Maybe Int
  , frEnv    :: Map Text Text
  }
  deriving (Eq, Show)

-- | The matched lines so far, per pattern id, in source order.
type Frames = Map Text [Frame]

noFrames :: Frames
noFrames = Map.empty

-- | Scope one matched line: which line heads its block, the bindings visible in
-- it, and the updated memory. @Left q@ means the line reads as an item of
-- pattern @q@ and no @q@ line precedes it -- deduce-or-fail, never a silent
-- reinterpretation as something else.
--
-- The child's own captures shadow its ancestors', so a child rebinding a name
-- means its own word. Its index is its position among the lines that matched
-- the SAME pattern under the SAME parent, so two blocks each number their own
-- items from one.
scopeLine :: Frames -> Pattern -> Int -> Int -> Map Text Text
          -> Either Text (Maybe Int, Map Text Text, Frames)
scopeLine frames p line indent own = case pParent p of
  Nothing -> Right (place Nothing Map.empty)
  Just q  -> case pick q of
    Nothing -> Left q
    Just fr -> Right (place (Just (frLine fr)) (frEnv fr))
  where
    mine = Map.findWithDefault [] (pId p) frames
    -- A pattern nested under itself has no other line to key on, so depth is
    -- the only thing that can say which instance encloses this one.
    pick q
      | q == pId p = lastOf [f | f <- mine, frIndent f < indent]
      | otherwise  = lastOf (Map.findWithDefault [] q frames)
    place par penv =
      let idx = 1 + length [f | f <- mine, frParent f == par]
          env = own `Map.union` indexBinds idx `Map.union` penv
       in ( par
          , env
          , Map.insertWith (flip (++)) (pId p) [Frame line indent par env] frames
          )
    indexBinds idx =
      Map.fromList [(n, T.pack (show idx)) | (n, SIndex) <- structHoles p]
    lastOf [] = Nothing
    lastOf xs = Just (last xs)
