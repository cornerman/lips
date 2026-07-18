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
-- > <template>  =>  <kind> <subject> <strength> "<assertion>"
--
-- Holes are written @\<name\>@ in the template, subject, and assertion. A hole
-- used in the subject or assertion must be bound by the template; that is
-- checked on read, so 'applyPattern' is total. Rule and demand sub-grammars
-- live in 'Lips.Engine.Data'. The engine round-trips:
-- @readLang . renderLang == Right@.
module Lips.Lang.Lang
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

import Lips.Engine.Data     (DemandSpec (..), MapRule (..), parseDemandBody,
                             parseRuleBody, renderDemandBody, renderRuleBody)
import Lips.Kernel.Base     (fromList, toList)
import Lips.Kernel.Decision
import Lips.Kernel.Reader   (ParseError (..), readBase, renderBase)
import Lips.Lang.Pattern

-- | A whole minted engine: the language (front half) and the semantics (back
-- half), as read from one @.lang@ file.
data EngineData = EngineData
  { edPatterns :: [Pattern]
  , edRules    :: [MapRule]
  , edDemands  :: [DemandSpec]
  }
  deriving (Eq, Show)

-- | Render an engine to canonical @.lang@ text, each group ordered by id.
renderLang :: EngineData -> Text
renderLang ed =
  renderBase . fromList $
    map patternToDecision (sortOn pId (edPatterns ed))
      ++ map ruleToDecision (sortOn mrId (edRules ed))
      ++ map demandToDecision (sortOn dsId (edDemands ed))

-- | Read an engine from @.lang@ text. Reuses the kernel reader for the
-- decision envelope, then parses each group's body sub-grammar. Decisions
-- outside the three groups are ignored, so a @.lang@ file may carry other
-- meta decisions later without breaking this reader.
readLang :: Text -> Either [ParseError] EngineData
readLang src = do
  base <- readBase src
  let ds = toList base
      patR = [ decisionToPattern d | d <- ds, isGroup ["lang", "pattern"] d ]
      rulR = [ bodyOf parseRuleBody d | d <- ds, isGroup ["engine", "rule"] d ]
      demR = [ bodyOf parseDemandBody d | d <- ds, isGroup ["engine", "demand"] d ]
      errs = [ ParseError 0 e | Left e <- patR ] ++ [ ParseError 0 e | Left e <- rulR ]
               ++ [ ParseError 0 e | Left e <- demR ]
  if null errs
    then Right EngineData
           { edPatterns = sortOn pId [p | Right p <- patR]
           , edRules    = sortOn mrId [r | Right r <- rulR]
           , edDemands  = sortOn dsId [q | Right q <- demR]
           }
    else Left errs
  where
    -- isGroup guarantees exactly (prefix + id) segments, so this is total.
    bodyOf parse d = case (dSubject d, dAssertion d) of
      (Subject [_, _, i], Assertion a) -> parse i a
      (Subject segs, _) -> Left ("malformed group subject: " <> T.intercalate "." segs)

isGroup :: [Text] -> Decision -> Bool
isGroup prefix d = case dSubject d of
  Subject segs -> prefix == take (length prefix) segs && length segs == length prefix + 1

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
    <> kindText (pKind p)
    <> " " <> renderParts (pSubject p)
    <> " " <> strengthText (pStrength p)
    <> " " <> quoteParts (pAssertion p)

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
  let (tplStr, afterArrow) = T.breakOn " => " body
  rest0 <- if T.null afterArrow
             then Left ("pattern " <> pid <> ": missing =>")
             else Right (T.drop 4 afterArrow)
  let template = map parseTplTok (T.words tplStr)
  (kindTok, r1) <- firstToken rest0 ("pattern " <> pid <> ": missing kind")
  (subjTok, r2) <- firstToken r1 ("pattern " <> pid <> ": missing subject")
  (strTok,  r3) <- firstToken r2 ("pattern " <> pid <> ": missing strength")
  kind <- maybe (Left ("pattern " <> pid <> ": unknown kind " <> kindTok)) Right (lookup kindTok kindTable)
  str  <- maybe (Left ("pattern " <> pid <> ": unknown strength " <> strTok)) Right (lookup strTok strengthTable)
  assn <- parseQuoted (T.stripStart r3)
  let subjectParts   = parseHoley subjTok
      assertionParts = parseHoley assn
      p = Pattern
            { pId = pid
            , pTemplate = template
            , pKind = kind
            , pStrength = str
            , pSubject = subjectParts
            , pAssertion = assertionParts
            }
  -- Every hole in the target must be bound by the template, so 'applyPattern'
  -- is total. Reject a pattern that would leave a hole dangling.
  let bound = holesOf p
      used  = [h | SHole h <- subjectParts] ++ [h | SHole h <- assertionParts]
      loose = filter (`notElem` bound) used
  if null loose
    then Right p
    else Left ("pattern " <> pid <> ": target holes not bound by template: " <> T.intercalate "," loose)

parseTplTok :: Text -> TplTok
parseTplTok w
  | Just h <- holeName w = THole h
  | otherwise            = TLit (normalizeToken w)

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
