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
--     ('Lips.Kernel.Lang.Pattern.pParents', spelled @p3.under.p2@);
--   * a matching line is then read as an item of the block headed by the
--     NEAREST PRECEDING line that matched that parent;
--   * that line's captures are in scope in the child, so a child's emitted
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
-- canonical @.decisions@ text are untouched: a block is a scope at crystallize
-- time, not a new decision shape. In particular no decision \"owns\" a list --
-- @Append@ ('Lips.Kernel.Engine.Aggregate') already assembles one from N
-- same-option contributors in source order.
--
-- Two shapes of nesting, one rule. A FINITE nesting has one pattern per level,
-- each naming the level above. An UNBOUNDED one (a tree of nodes) names two
-- parents in order, @n1.under.n1.under.n0@: itself first, so an indented item
-- sits inside the item above it, and the header second, so an outermost item
-- roots in the block. Depth is the one place leading whitespace carries
-- meaning, and only for that self-reference; every other pattern ignores it, as
-- lips always has. Keys compose through @\<k:key\>@, so a node three deep keys
-- as @tree.File.New.Item@ and two subtrees may share a node name.
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
  , recordLine
  ) where

import           Data.List       (find, nub, sort)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Lang.Pattern (PatEmit (..), Pattern (..), StrPart (..),
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
  | -- | Emit holes bound by neither this pattern nor every block it can sit in,
    -- so 'Lips.Kernel.Lang.Pattern.applyPattern' could not fill them.
    UnboundInScope Text [Text]
  | -- | A top-level pattern declaring @\<k:key\>@: there is no enclosing line
    -- for it to name.
    KeyWithoutBlock Text
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
    <> ">, which neither it nor every block it can sit in binds"
renderNestError (KeyWithoutBlock p) =
  "pattern " <> p <> " names <key>, but it nests under nothing, so it heads no block"

-- | The patterns enclosing this one, nearest first, excluding itself. Follows
-- the FIRST declared parent, which is the nesting a reader means by \"the block
-- above\"; a self-reference is skipped (it binds the same names). Total on any
-- engine: it stops at a missing parent and at a repeat, so a malformed engine
-- yields a short list rather than a loop ('checkNesting' is what refuses it).
ancestorsOf :: [Pattern] -> Pattern -> [Pattern]
ancestorsOf pats p = go (foreign' p) [pId p]
  where
    foreign' q = [x | x <- pParents q, x /= pId q]
    go [] _ = []
    go (q : _) seen
      | q `elem` seen = []
      | otherwise = case find ((== q) . pId) pats of
          Nothing -> []
          Just a  -> a : go (foreign' a) (q : seen)

-- | Every hole name a pattern may reference: the ones its own template binds,
-- the structure-bound ones it declares, and -- for a pattern that may sit in
-- several kinds of block -- only the names EVERY one of those blocks binds. The
-- intersection, not the union, because the line attaches to whichever parent it
-- finds, so a name only one parent binds could be unfilled at run time.
--
-- This is the set 'Lips.Kernel.Lang.Pattern.applyPattern' will find filled, so
-- the static gates ('Lips.Kernel.Engine.Reach',
-- 'Lips.Kernel.Engine.Answerable') build their marker bindings from it rather
-- than from the template alone.
holesInScope :: [Pattern] -> Pattern -> [Text]
holesInScope pats = nub . go []
  where
    go seen p
      | pId p `elem` seen = own p
      | otherwise = own p ++ inherited (pId p : seen) p
    own a = holesOf a ++ map fst (structHoles a)
    -- A self-reference contributes nothing beyond the pattern's own names.
    inherited seen p = case [q | q <- pParents p, q /= pId p] of
      []      -> []
      parents -> case [go seen a | q <- parents, Just a <- [find ((== q) . pId) pats]] of
        []       -> []
        (s : ss) -> foldl' intersect' s ss
    intersect' a b = [x | x <- a, x `elem` b]

-- | Every way an engine's nesting fails to close, in pattern-id order so the
-- report is deterministic. Empty means every child has a parent, no cycle
-- exists, and every emit hole is bound by the pattern or by every block it can
-- sit in.
checkNesting :: [Pattern] -> [NestError]
checkNesting pats =
  concatMap unknown ordered ++ cycles ++ concatMap keyless ordered ++ concatMap unbound ordered
  where
    ordered = map snd (Map.toAscList (Map.fromList [(pId p, p) | p <- pats]))
    known q = any ((== q) . pId) pats
    unknown p = [UnknownParent (pId p) q | q <- pParents p, not (known q)]
    keyless p =
      [ KeyWithoutBlock (pId p)
      | null (pParents p), not (null [() | (_, SKey) <- structHoles p]) ]
    cycles = map NestCycle (nub (sort (concatMap cycleAt ordered)))
    unbound p =
      let scope = holesInScope pats p
          used  = nub [ refName h
                      | e <- pEmits p
                      , SHole h <- peSubject e ++ peAssertion e ]
          loose = filter (`notElem` scope) used
       in [UnboundInScope (pId p) loose | not (null loose)]
    -- Walk the FOREIGN parent chain (a self-reference is depth, not a cycle).
    -- Coming back to a pattern already on the walk is a cycle, reported rotated
    -- to its smallest id so both members report the same one.
    cycleAt p = go [q | q <- pParents p, q /= pId p] [pId p]
      where
        go [] _ = []
        go (q : _) seen
          | q `elem` seen = [rotate (dropWhile (/= q) seen)]
          | otherwise = case find ((== q) . pId) pats of
              Nothing -> []
              Just a  -> go [x | x <- pParents a, x /= pId a] (seen ++ [q])
    rotate ids = case sort ids of
      (m : _) -> dropWhile (/= m) ids ++ takeWhile (/= m) ids
      []      -> ids

-- | What crystallize remembers about one matched line so later lines can scope
-- to it: where it was, how deep, which line heads its own block, the bindings
-- visible inside it, and the subject it is keyed by (its first emit's).
data Frame = Frame
  { frLine   :: Int
  , frIndent :: Int
  , frParent :: Maybe Int
  , frEnv    :: Map Text Text
  , frKey    :: Text
  }
  deriving (Eq, Show)

-- | The matched lines so far, per pattern id, in source order.
type Frames = Map Text [Frame]

noFrames :: Frames
noFrames = Map.empty

-- | Scope one matched line: which line heads its block, and the bindings visible
-- in it. @Left qs@ means the line reads as an item of one of the patterns @qs@
-- and none of them precedes it -- deduce-or-fail, never a silent
-- reinterpretation as something else.
--
-- Parents are tried in declared order. A SELF-reference matches the nearest
-- preceding line of this same pattern that is less indented, which is the only
-- thing that can say how deep an item sits; any other parent matches its nearest
-- preceding line, whatever the indentation.
--
-- The child's own captures shadow its ancestors', so a child rebinding a name
-- means its own word. Its index is its position among the lines that matched the
-- SAME pattern in the SAME block, so two blocks each number their items from
-- one.
scopeLine :: Frames -> Pattern -> Int -> Map Text Text
          -> Either [Text] (Maybe Int, Map Text Text)
scopeLine frames p indent own = case pParents p of
  []      -> Right (Nothing, bind Nothing Map.empty "")
  parents -> case [fr | q <- parents, Just fr <- [pick q]] of
    (fr : _) -> Right (Just (frLine fr), bind (Just (frLine fr)) (frEnv fr) (frKey fr))
    []       -> Left parents
  where
    mine = Map.findWithDefault [] (pId p) frames
    pick q
      | q == pId p = lastOf [f | f <- mine, frIndent f < indent]
      | otherwise  = lastOf (Map.findWithDefault [] q frames)
    bind par penv pkey =
      own `Map.union` structBinds par pkey `Map.union` penv
    structBinds par pkey = Map.fromList
      [ (n, val)
      | (n, st) <- structHoles p
      , let val = case st of
              SIndex -> T.pack (show (1 + length [f | f <- mine, frParent f == par]))
              SKey   -> pkey
      ]
    lastOf [] = Nothing
    lastOf xs = Just (last xs)

-- | Remember a scoped line, so the lines after it can sit in its block. Called
-- once the line's decisions exist, since a line's block key is the subject of
-- its first emit -- what a child's @\<k:key\>@ resolves to.
recordLine :: Frames -> Pattern -> Int -> Int -> Maybe Int -> Map Text Text -> Text -> Frames
recordLine frames p line indent par env key =
  Map.insertWith (flip (++)) (pId p) [Frame line indent par env key] frames
