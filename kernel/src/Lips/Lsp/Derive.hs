{-# LANGUAGE OverloadedStrings #-}

-- | The pure core of the language server: turn a language (its patterns) and a
-- program's 'Diagnosis' into the two things an editor shows -- completion items
-- and diagnostics -- as plain typed values, with no JSON and no IO. The server
-- shell ('Lips.Lsp.Server') maps these to the wire protocol. Keeping this pure
-- is functional-core/imperative-shell: the interesting logic is testable
-- without a socket, and it reuses the very same 'diagnose' that @lips check@
-- prints, so the editor never disagrees with the CLI.
module Lips.Lsp.Derive
  ( CItem (..)
  , completionItems
  , completionItemsAt
  , Diag (..)
  , diagsOf
  ) where

import           Data.Char       (isSpace)
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Text       (Text)
import qualified Data.Text       as T

import Lips.Kernel.Lang.Crystallize (LineOutcome (..))
import Lips.Kernel.Lang.Diagnose    (Diagnosis (..))
import Lips.Kernel.Lang.Pattern     (FusedSeg (..), Pattern (..), TplTok (..),
                                     matchFused, normalizeToken, tokenizeLine)

-- | One completion candidate: the human-readable sentence form of a pattern,
-- and a snippet with numbered tab-stops for its holes.
data CItem = CItem
  { ciLabel   :: Text -- ^ e.g. @back up \<src\> to \<dst\> daily@
  , ciSnippet :: Text -- ^ e.g. @back up ${1:src} to ${2:dst} daily@
  }
  deriving (Eq, Show)

-- | Every pattern in the language becomes one candidate, with all holes as
-- numbered tab-stops. This is the no-context case (an empty line, or a cursor
-- before any typed token): the editor offers every sentence form and the
-- client filters by prefix. The contextual case ('completionItemsAt') reaches
-- the same shape for an empty prefix, so the two share one renderer.
completionItems :: [Pattern] -> [CItem]
completionItems = map (renderPattern Map.empty)

-- | Contextual completion: complete the sentence a line has already started.
-- @line@ is the whole current line and @col@ is the 0-based cursor column. A
-- pattern is offered only when its template admits the typed prefix and still
-- has something left to complete (the prefix has not already matched it
-- whole). Already-typed holes are filled as literals; only the holes still to
-- type become tab-stops, numbered in template order.
--
-- The match reuses the template grammar ('tokenizeLine' for the typed side),
-- so the kernel stays domain-blind: it knows nothing about any program's
-- words, only that a literal must equal a typed token and a hole binds one. A
-- fragment at the cursor (the cursor mid-word) is matched positionally: it
-- completes a literal it is a prefix of, or fills the hole at that position.
completionItemsAt :: [Pattern] -> Text -> Int -> [CItem]
completionItemsAt pats line col =
  [ renderPattern binds p
  | p <- pats
  , let (toks, mfrag) = splitPrefix prefix
  , Just (binds, remaining) <- [matchPrefix (pTemplate p) toks mfrag]
  , not (null remaining)            -- nothing left to complete -> skip
  ]
  where
    prefix = T.take (max 0 col) line

-- | Split a line prefix into the complete tokens (everything the cursor has
-- passed) and an optional trailing fragment (the partial word the cursor sits
-- in). At a token boundary (after a space, or at line start) there is no
-- fragment: the next template token is entirely unstarted. The fragment is
-- kept raw and normalized only when matched, so a captured hole value keeps
-- its case and a literal-prefix comparison uses the same normalization as the
-- template side.
splitPrefix :: Text -> ([(Text, Text)], Maybe Text)
splitPrefix prefix
  | T.null prefix || isSpace (T.last prefix) = (tokenizeLine prefix, Nothing)
  | otherwise =
      let (before, frag) = T.breakOnEnd " " prefix
       in (tokenizeLine before, Just frag)

-- | Match a typed prefix against a template, returning the bindings collected
-- so far and the template suffix still to complete. Two phases: the complete
-- tokens (everything except a possible trailing fragment) are matched like
-- 'Lips.Kernel.Lang.Pattern.matchTemplate' but the token list may run out
-- early; then a trailing fragment, if any, is matched positionally against the
-- next template token. @Nothing@ means the typed prefix is not a valid prefix
-- of this pattern (a literal mismatched, or the line has tokens the template
-- cannot account for).
matchPrefix :: [TplTok] -> [(Text, Text)] -> Maybe Text
            -> Maybe (Map Text Text, [TplTok])
matchPrefix tpl toks mfrag = do
  (binds, remaining) <- matchComplete tpl toks Map.empty
  applyPartial binds remaining mfrag

-- | Phase 1: match complete tokens. The token list may run out before the
-- template (returning the leftover template as the suffix to complete); a
-- literal must equal, a hole binds one token, and a trailing tail hole binds
-- the rest (and so consumes the template). Running out of tokens at a tail
-- hole leaves the tail unfilled (it needs at least one token, which the
-- fragment or further typing will supply). The template running out while
-- tokens remain means the line has outgrown the pattern (a tail would have
-- consumed them), so it is not a valid prefix.
matchComplete :: [TplTok] -> [(Text, Text)] -> Map Text Text
              -> Maybe (Map Text Text, [TplTok])
matchComplete tpl []           binds = Just (binds, tpl)   -- tokens ran out
matchComplete []  _            _     = Nothing             -- template outgrown
matchComplete (TLit lit : ts) ((_, norm) : rs) binds
  | lit == norm = matchComplete ts rs binds
  | otherwise   = Nothing
matchComplete (THole h : ts) ((surface, _) : rs) binds =
  matchComplete ts rs (Map.insert h surface binds)
-- A fused token is one token: it either matches whole, or the line is not a
-- prefix of this pattern.
matchComplete (TFused segs : ts) ((surface, _) : rs) binds =
  case matchFused segs surface of
    Just caps -> matchComplete ts rs (foldr (uncurry Map.insert) binds caps)
    Nothing   -> Nothing
matchComplete (TMulti h : ts) rest binds
  | null rest  = Just (binds, TMulti h : ts)   -- tokens ran out: hole unfilled
  | otherwise  = case ts of
      -- Last token: it takes everything that is left.
      [] -> Just (Map.insert h (T.unwords (map fst rest)) binds, [])
      -- Bounded: take the words up to the first token the next literal
      -- matches. Completion is best-effort by nature (the line is half
      -- written), so it scans once instead of backtracking like
      -- 'matchTemplate'; the worst case is a candidate not offered.
      (TLit lit : ts') -> case break ((== lit) . snd) rest of
        (taken, _ : rs) | not (null taken) ->
          matchComplete ts' rs (Map.insert h (T.unwords (map fst taken)) binds)
        _ -> Just (Map.insert h (T.unwords (map fst rest)) binds, ts)
      _ -> Just (Map.insert h (T.unwords (map fst rest)) binds, ts)

-- | Phase 2: match the trailing fragment (the partial word at the cursor)
-- against the next template token, positionally. A literal admits the fragment
-- if it is a prefix of it (the snippet will complete the word); if the
-- fragment already equals the literal (normalized), the literal is fully typed
-- and the suffix advances past it. A hole or tail binds the fragment (it is a
-- value the user is typing). @Nothing@ discards patterns the prefix has
-- already outgrown (a fragment with no template token left to receive it).
applyPartial :: Map Text Text -> [TplTok] -> Maybe Text
             -> Maybe (Map Text Text, [TplTok])
applyPartial binds remaining Nothing = Just (binds, remaining)
applyPartial binds remaining (Just frag) = case remaining of
  (TLit lit : ts)
    | norm == lit          -> Just (binds, ts)               -- fully typed: advance
    | T.isPrefixOf norm lit -> Just (binds, remaining)        -- partial: complete it
    | otherwise             -> Nothing
  (THole h : ts)
    | not (T.null frag) -> Just (Map.insert h frag binds, ts)
    | otherwise         -> Nothing
  (TMulti h : ts)
    | not (T.null frag) -> Just (Map.insert h frag binds, ts)
    | otherwise         -> Nothing
  -- A half-typed fused token cannot bind yet (its closing literal is missing),
  -- so it stays as the suffix to complete.
  (TFused _ : _)         -> Just (binds, remaining)
  []                    -> Nothing                          -- prefix outgrew template
  where norm = normalizeToken frag

-- | Render a pattern as a completion candidate. A hole already filled (in the
-- binding map) appears as its captured surface text (a literal, no tab-stop,
-- since the user already typed it); a hole still to type becomes a numbered
-- tab-stop. Tab-stop numbers are assigned by hole name, so a repeated hole
-- stays in sync across its occurrences. A multi-token hole uses the @\<name.words>@
-- label form when unfilled, matching the no-context renderer.
renderPattern :: Map Text Text -> Pattern -> CItem
renderPattern binds p =
  let (labels, snips, _) = foldl step ([], [], Map.empty) (pTemplate p)
   in CItem (T.unwords (reverse labels)) (T.unwords (reverse snips))
  where
    step (ls, ss, nums) (TLit t)   = (t : ls, t : ss, nums)
    step (ls, ss, nums) (THole h)  = holeStep ls ss nums h False
    step (ls, ss, nums) (TMulti h) = holeStep ls ss nums h True
    -- A fused token is one word: its literal pieces are typed as they stand and
    -- each hole inside it becomes its own tab-stop.
    step (ls, ss, nums) (TFused segs) =
      let (l, s, nums') = foldl fusedStep ("", "", nums) segs
       in (l : ls, s : ss, nums')
    fusedStep (l, s, nums) (FLit t)  = (l <> t, s <> t, nums)
    fusedStep (l, s, nums) (FHole h) = case Map.lookup h binds of
      Just v  -> (l <> v, s <> v, nums)
      Nothing -> let (n, nums') = assign h nums
                  in (l <> "<" <> h <> ">", s <> "${" <> T.pack (show n) <> ":" <> h <> "}", nums')
    holeStep ls ss nums h isMulti =
      case Map.lookup h binds of
        Just v  -> (v : ls, v : ss, nums)                -- filled: literal
        Nothing ->
          let (n, nums') = assign h nums
              label = if isMulti then "<" <> h <> ".words>" else "<" <> h <> ">"
              tab   = "${" <> T.pack (show n) <> ":" <> h <> "}"
           in (label : ls, tab : ss, nums')
    -- Assign a stable number per hole name so repeated holes share a tab-stop.
    assign h nums = case Map.lookup h nums of
      Just n  -> (n, nums)
      Nothing -> let n = Map.size nums + 1 in (n, Map.insert h n nums)

-- | One diagnostic: a whole-line span (0-based line, character range) with a
-- severity (LSP: 1 error, 2 warning) and a message.
data Diag = Diag
  { dgLine     :: Int
  , dgStart    :: Int
  , dgEnd      :: Int
  , dgSeverity :: Int
  , dgMessage  :: Text
  }
  deriving (Eq, Show)

-- | Diagnostics for a program: a line the language cannot read, or reads
-- ambiguously, is an error on that line; a demand left open is a
-- whole-program warning (surfaced on the first line, since it belongs to no
-- single line). A cleanly matched line yields nothing.
diagsOf :: Diagnosis -> [Diag]
diagsOf d = concatMap lineDiag (diagLines d) ++ map openDiag (diagOpen d)
  where
    lineDiag (Matched {})       = []
    lineDiag (Unmatched n t)    =
      [Diag (n - 1) 0 (T.length t) 1
        "No pattern reads this line. Run: lips generate <program>"]
    lineDiag (Ambiguous n _ ids) =
      [Diag (n - 1) 0 0 1
        ("This line matches several patterns (" <> T.intercalate ", " ids
          <> "); the language is not orthogonal here.")]
    lineDiag (Orphan n t qs) =
      [Diag (n - 1) 0 (T.length t) 1
        ("This line is an item of a block, and no line above it opens one ("
          <> T.intercalate " or " qs <> ").")]
    openDiag q = Diag 0 0 0 2 ("Open question: " <> q)
