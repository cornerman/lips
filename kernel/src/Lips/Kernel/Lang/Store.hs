{-# LANGUAGE OverloadedStrings #-}

-- | The stored form of a minted engine: the @.lang@ file (spec v2, section 5;
-- crystallization + engine-synthesis plans). One file carries the whole
-- engine, in the same canonical decision text as everything else, so
-- regeneration is atomic and the halves cannot drift:
--
-- > lang.pattern.<id>   front half: loose line -> decision
-- > engine.rule.<id>    back half:  decision -> ground option assignments
-- > engine.demand.<id>  back half:  required subject + question
--
-- Pattern sub-grammar inside the assertion:
--
-- > <template>  =>  <kind> <subject> <strength> "<assertion>" ; <kind> <subject> <strength> "<assertion>" ...
--
-- A pattern emits one decision per @ ; @-separated clause (mirroring the rule
-- back half), so one dense loose line can state several facts. A single emit
-- renders with no @ ; @, identical to the pre-multi-emit form, so older engines
-- still read.
--
-- Holes are written @\<name\>@ in the template, subject, and assertion. A hole
-- used in the subject or assertion must be bound by the template; that is
-- checked on read, so 'applyPattern' is total. Rule and demand sub-grammars
-- live in 'Lips.Kernel.Engine.Data'. The engine round-trips:
-- @readLang . renderLang == Right@.
module Lips.Kernel.Lang.Store
  ( EngineData (..)
  , renderLang
  , readLang
  , patternToDecision
  , decisionToPattern
  , parsePatternBody
  ) where

import           Data.List  (sortOn)
import           Data.Text  (Text)
import qualified Data.Text  as T

import Lips.Kernel.Engine.Data     (DemandSpec (..), MapRule (..), parseDemandBody,
                             parseRuleBody, renderDemandBody, renderRuleBody)
import Lips.Kernel.Base     (fromList)
import Lips.Kernel.Decision
import Lips.Kernel.Reader   (ParseError (..), readDecision, renderBase)
import Lips.Kernel.Lang.Pattern

-- | A whole minted engine: the language (front half) and the semantics (back
-- half), as read from one @.lang@ file.
data EngineData = EngineData
  { edPatterns :: [Pattern]
  , edRules    :: [MapRule]
  , edDemands  :: [DemandSpec]
  }
  deriving (Eq, Show)

-- | Render an engine to canonical @.lang@ text, each group ordered by id.
-- Every line carries the given provenance -- for minted engines the
-- generation-event stamp ('FromGeneration'), so each engine decision names
-- the pinned event that produced it.
renderLang :: Provenance -> EngineData -> Text
renderLang prov ed =
  renderBase . fromList . map stamp $
    map patternToDecision (sortOn pId (edPatterns ed))
      ++ map ruleToDecision (sortOn mrId (edRules ed))
      ++ map demandToDecision (sortOn dsId (edDemands ed))
  where
    stamp d = d { dProv = prov }

-- | One classified engine line: which group a @.lang@ decision belongs to.
data EngLine = ELPat Pattern | ELRule MapRule | ELDem DemandSpec

-- | Read an engine from @.lang@ text in one line-aware pass, so every error
-- (envelope or body sub-grammar) names its real source line, not line 0.
-- Every non-blank, non-comment line must be a recognized engine decision
-- (@lang.pattern.*@, @engine.rule.*@, @engine.demand.*@); anything else fails
-- loud rather than being silently dropped -- a corrupted or mistyped @.lang@
-- must not lose a rule quietly (deduce-or-fail).
readLang :: Text -> Either [ParseError] EngineData
readLang src =
  let cands   = [ (n, t) | (n, l) <- zip [1 ..] (T.lines src)
                         , let t = T.strip l, not (skip t) ]
      results = map (uncurry readEngineLine) cands
      errs    = [ e | Left e <- results ]
      oks     = [ x | Right x <- results ]
   in if null errs
        then Right EngineData
               { edPatterns = sortOn pId  [p | ELPat p  <- oks]
               , edRules    = sortOn mrId [r | ELRule r <- oks]
               , edDemands  = sortOn dsId [q | ELDem q  <- oks]
               }
        else Left errs
  where
    skip t = T.null t || "#" `T.isPrefixOf` t
    -- Read the decision envelope (re-stamping its line), then classify and
    -- parse the group body -- both errors anchored to the real line n.
    readEngineLine n t = do
      d <- either (\pe -> Left pe { peLine = n }) Right (readDecision t)
      classify n d

classify :: Int -> Decision -> Either ParseError EngLine
classify n d = case dSubject d of
  Subject ["lang", "pattern", i]   -> tag ELPat  (parsePatternBody i body)
  Subject ["engine", "rule", i]    -> tag ELRule (parseRuleBody   i body)
  Subject ["engine", "demand", i]  -> tag ELDem  (parseDemandBody i body)
  Subject segs -> Left (ParseError n
    ("unrecognized engine line (subject " <> T.intercalate "." segs
      <> "): a .lang carries only lang.pattern.*, engine.rule.*, engine.demand.*"))
  where
    body = case dAssertion d of Assertion a -> a
    tag f = either (Left . ParseError n) (Right . f)

-- | Turn a rule into its canonical @meta@ decision.
ruleToDecision :: MapRule -> Decision
ruleToDecision r = metaDecision (mrId r) ["engine", "rule", mrId r] (renderRuleBody r)

-- | Turn a demand into its canonical @meta@ decision.
demandToDecision :: DemandSpec -> Decision
demandToDecision q = metaDecision (dsId q) ["engine", "demand", dsId q] (renderDemandBody q)

metaDecision :: Text -> [Text] -> Text -> Decision
metaDecision i segs body =
  Decision
    { dId        = DecisionId i
    , dSubject   = Subject segs
    , dKind      = Meta
    , dAssertion = Assertion body
    , dStrength  = Stated
    , dProv      = FromSource (SourceLoc "lang" 0)
    , dRationale = Nothing
    }

-- | Turn a pattern into its canonical @meta@ decision.
patternToDecision :: Pattern -> Decision
patternToDecision p = metaDecision (pId p) ["lang", "pattern", pId p] (renderBody p)

-- | Parse a @lang.pattern.*@ decision back into a pattern, or explain why not.
decisionToPattern :: Decision -> Either Text Pattern
decisionToPattern d = do
  pid <- case dSubject d of
    Subject ["lang", "pattern", i] -> Right i
    _ -> Left "not a lang.pattern subject"
  parseBody pid (unAssertion (dAssertion d))
  where
    unAssertion (Assertion a) = a

-- Body grammar: @<template> => <kind> <subject> <strength> "<assertion>"@.

-- | Parse a pattern body (the sub-grammar) given its id. Exposed so @generate@
-- can read the patterns a model mints in exactly the stored form.
parsePatternBody :: Text -> Text -> Either Text Pattern
parsePatternBody = parseBody

renderBody :: Pattern -> Text
renderBody p =
  T.unwords (map renderTplTok (pTemplate p))
    <> " => "
    <> T.intercalate " ; " (map renderEmit (pEmits p))
  where
    renderEmit e =
      kindText (peKind e)
        <> " " <> renderParts (peSubject e)
        <> " " <> strengthText (peStrength e)
        <> " " <> quoteParts (peAssertion e)

renderTplTok :: TplTok -> Text
renderTplTok (TLit t)  = t
renderTplTok (THole h) = "<" <> h <> ">"

renderParts :: [StrPart] -> Text
renderParts = T.concat . map r
  where
    r (SLit t)  = t
    r (SHole h) = "<" <> h <> ">"

quoteParts :: [StrPart] -> Text
quoteParts ps = "\"" <> T.concatMap esc (renderParts ps) <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = T.singleton c

parseBody :: Text -> Text -> Either Text Pattern
parseBody pid body = do
  (tplStr, rest0) <- maybe (Left ("pattern " <> pid <> ": missing =>")) Right
                       (splitOnSeparator body)
  -- Drop empty-literal tokens (pure punctuation), symmetric with 'tokenizeLine',
  -- so a period glued to a quoted value never survives as a phantom token that
  -- would unbalance the match after a render/read round-trip.
  let template = filter (not . emptyLit) (map parseTplTok (lexTokens tplStr))
      emptyLit (TLit t) = T.null t
      emptyLit _        = False
  emits <- mapM (parseEmit . T.strip) (splitEmits rest0)
  let p = Pattern { pId = pid, pTemplate = template, pEmits = emits }
  -- Every hole in the target must be bound by the template, so 'applyPattern'
  -- is total. Reject a pattern that would leave any emit's hole dangling.
  let bound = holesOf p
      used  = concat [ [h | SHole h <- peSubject e] ++ [h | SHole h <- peAssertion e] | e <- emits ]
      loose = filter (`notElem` bound) used
  if null loose
    then Right p
    else Left ("pattern " <> pid <> ": target holes not bound by template: " <> T.intercalate "," loose)
  where
    parseEmit t = do
      (kindTok, r1) <- firstToken t ("pattern " <> pid <> ": missing kind")
      (subjTok, r2) <- firstToken r1 ("pattern " <> pid <> ": missing subject")
      (strTok,  r3) <- firstToken r2 ("pattern " <> pid <> ": missing strength")
      kind <- maybe (Left ("pattern " <> pid <> ": unknown kind " <> kindTok)) Right (lookup kindTok kindTable)
      str  <- maybe (Left ("pattern " <> pid <> ": unknown strength " <> strTok)) Right (lookup strTok strengthTable)
      assn <- parseQuoted (T.stripStart r3)
      Right (PatEmit kind str (parseHoley subjTok) (parseHoley assn))

-- The pattern body is @<template> => <decision>@, but a template may itself
-- contain @=>@ (route arrows, lambdas and mappings are common domain syntax).
-- The decision grammar (@<kind> <subject> <strength> "<assertion>"@) never
-- contains @ => @ outside its quoted assertion, so the meta-separator is always
-- the LAST @ => @ lying outside quotes. Splitting there lets a template use
-- @=>@ freely: the kernel's own delimiter must not forbid a surface form.
splitOnSeparator :: Text -> Maybe (Text, Text)
splitOnSeparator body =
  case [ (b, T.drop 4 a) | (b, a) <- T.breakOnAll " => " body, even (unescapedQuotes b) ] of
    [] -> Nothing
    xs -> Just (last xs)

-- | Split a pattern's emit clauses on the @ ; @ that lies OUTSIDE quotes, so an
-- assertion may itself contain @"; "@. Leftmost-first, quote-aware; the naive
-- @T.splitOn@ the rule body uses would mis-split such an emit.
splitEmits :: Text -> [Text]
splitEmits t =
  case [ (b, T.drop 3 a) | (b, a) <- T.breakOnAll " ; " t, even (unescapedQuotes b) ] of
    []          -> [t]
    ((b, a) : _) -> b : splitEmits a

-- | Count unescaped double quotes in a prefix, so a scan can tell whether a
-- split point lies inside a quoted span (odd count) or outside it (even).
unescapedQuotes :: Text -> Int
unescapedQuotes t = go (T.unpack t) (0 :: Int)
  where
    go []              n = n
    go ('\\' : _ : cs) n = go cs n
    go ('"' : cs)      n = go cs (n + 1)
    go (_ : cs)        n = go cs n

parseTplTok :: Text -> TplTok
parseTplTok w
  -- A quoted span in the template: "<body>" captures a quoted value (its
  -- inner text, spaces and all); a fixed "literal" matches a quoted token.
  -- Symmetric with 'tokenizeLine', which lexes a quoted line value as one
  -- token, so the two line up.
  | Just inner <- unquote w = maybe (TLit (T.toLower inner)) THole (holeName inner)
  -- Symmetric with 'tokenizeLine': trailing sentence punctuation is noise on
  -- the template side too, so a minted "<when>." is the hole <when> (live
  -- mints glue the line's final period onto the hole; kernel physics, not a
  -- prompt plea).
  | Just h <- holeName (stripTrailingPunct w) = THole h
  | otherwise                                 = TLit (normalizeToken w)

-- | Parse a holey string (literal text with @\<name\>@ holes) into parts.
parseHoley :: Text -> [StrPart]
parseHoley t
  | T.null t = []
  | otherwise =
      case T.breakOn "<" t of
        (before, rest)
          | T.null rest -> [SLit before | not (T.null before)]
          | otherwise ->
              let (holeBody, afterClose) = T.breakOn ">" (T.drop 1 rest)
               in if T.null afterClose
                    then [SLit t] -- unterminated hole: treat literally, stays visible
                    else [SLit before | not (T.null before)]
                           ++ [SHole holeBody]
                           ++ parseHoley (T.drop 1 afterClose)

holeName :: Text -> Maybe Text
holeName w = do
  b <- T.stripPrefix "<" w
  T.stripSuffix ">" b

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseQuoted :: Text -> Either Text Text
parseQuoted t = case T.uncons t of
  Just ('"', rest) -> go rest T.empty
  _                -> Left "expected quoted assertion"
  where
    go s acc = case T.uncons s of
      Nothing           -> Left "unterminated assertion"
      Just ('"', _)     -> Right acc
      Just ('\\', more) -> case T.uncons more of
        Just (c, more') -> go more' (T.snoc acc c)
        Nothing         -> Left "dangling escape"
      Just (c, more)    -> go more (T.snoc acc c)

kindTable :: [(Text, Kind)]
kindTable = [(kindText k, k) | k <- [minBound .. maxBound]]

strengthTable :: [(Text, Strength)]
strengthTable = [(strengthText s, s) | s <- [minBound .. maxBound]]

kindText :: Kind -> Text
kindText = T.toLower . T.pack . show

strengthText :: Strength -> Text
strengthText = T.toLower . T.pack . show
