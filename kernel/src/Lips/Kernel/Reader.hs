{-# LANGUAGE OverloadedStrings #-}

-- | The canonical stored form of a decision base: plain, diffable text, one
-- decision per line, so that a text diff approximates a set diff (spec v2,
-- section 2, \"notation dissolves\", and the walk-through's canonical-form
-- rules). This is /not/ the loose authoring text; turning loose text into
-- decisions is @generate@ (the one AI step). This reader is deterministic and
-- total, and it round-trips with 'render': @readBase . renderBase == id@.
--
-- Line grammar (comments start with @#@, blank lines ignored):
--
-- > <id> <kind> <subject> <strength> "<assertion>" [<provenance>] [-- <rationale>]
--
-- where @<subject>@ is a dotted path (@account.balance@), @<kind>@ and
-- @<strength>@ are the lowercased constructor names, the assertion is a quoted
-- string (@\\\"@ and @\\\\@ escaped), and @<provenance>@ is either
-- @\@file:line@ for a human decision or @<-id1,id2 via ruleId@ for a derived
-- one. A single decision occupies a single line by construction.
module Lips.Kernel.Reader
  ( ParseError (..)
  , readBase
  , readDecision
  , render
  , renderBase
  ) where

import           Data.List       (sortOn)
import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Kernel.Base     (Base, fromList, toList)
import Lips.Kernel.Decision

-- | A parse failure, anchored to the 1-based source line so the report is
-- never silent (fail loud).
data ParseError = ParseError
  { peLine    :: Int
  , peMessage :: Text
  }
  deriving (Eq, Show)

-- | Read a whole base, collecting every line error. Comment and blank lines
-- are skipped. Ids are expected unique; duplicates collapse under set
-- semantics, matching 'fromList'.
readBase :: Text -> Either [ParseError] Base
readBase src =
  let numbered = zip [1 ..] (T.lines src)
      candidates = [(n, t) | (n, l) <- numbered, let t = T.strip l, not (skip t)]
      results = map (\(n, t) -> either (Left . ParseError n) Right (parseLine t)) candidates
      errs = [e | Left e <- results]
      ds   = [d | Right d <- results]
   in if null errs then Right (fromList ds) else Left errs
  where
    skip t = T.null t || "#" `T.isPrefixOf` t

-- | Read one decision line (already stripped of surrounding space).
readDecision :: Text -> Either ParseError Decision
readDecision t = either (Left . ParseError 0) Right (parseLine t)

-- Internal parse producing a plain message; callers attach the line number.
parseLine :: Text -> Either Text Decision
parseLine line0 = do
  (idTok, r1)     <- token line0 "missing id"
  (kindTok, r2)   <- token r1 "missing kind"
  (subjTok, r3)   <- token r2 "missing subject"
  (strTok, r4)    <- token r3 "missing strength"
  kind            <- parseKind kindTok
  str             <- parseStrength strTok
  (assertion, r5) <- parseQuoted (T.stripStart r4)
  (prov, rat)     <- parseTail (T.stripStart r5)
  pure
    Decision
      { dId        = DecisionId idTok
      , dSubject   = Subject (T.splitOn "." subjTok)
      , dKind      = kind
      , dAssertion = Assertion assertion
      , dStrength  = str
      , dProv      = prov
      , dRationale = rat
      }

-- | Take one whitespace-delimited token from the front.
token :: Text -> Text -> Either Text (Text, Text)
token t err =
  case T.words t of
    [] -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseKind :: Text -> Either Text Kind
parseKind w = maybe (Left ("unknown kind: " <> w)) Right (lookup w kindTable)

parseStrength :: Text -> Either Text Strength
parseStrength w = maybe (Left ("unknown strength: " <> w)) Right (lookup w strengthTable)

-- | Parse a leading quoted string with @\\\"@ and @\\\\@ escapes.
parseQuoted :: Text -> Either Text (Text, Text)
parseQuoted t = case T.uncons t of
  Just ('"', rest) -> go rest T.empty
  _                -> Left "expected quoted assertion"
  where
    go s acc = case T.uncons s of
      Nothing          -> Left "unterminated assertion"
      Just ('"', rest) -> Right (acc, rest)
      Just ('\\', rest) -> case T.uncons rest of
        Just (c, rest') -> go rest' (T.snoc acc c)
        Nothing         -> Left "dangling escape in assertion"
      Just (c, rest)   -> go rest (T.snoc acc c)

-- | Parse the optional trailing provenance and rationale. Absent provenance
-- defaults to an unknown source at line 0, kept explicit rather than silent.
parseTail :: Text -> Either Text (Provenance, Maybe Text)
parseTail t
  | T.null t = Right (FromSource (SourceLoc "" 0), Nothing)
  | otherwise =
      let (provPart, ratPart) = breakRationale t
       in do
            prov <- if T.null (T.strip provPart)
                      then Right (FromSource (SourceLoc "" 0))
                      else parseProvenance (T.strip provPart)
            pure (prov, ratPart)

-- | Split at the first @--@ rationale marker.
breakRationale :: Text -> (Text, Maybe Text)
breakRationale t =
  case T.breakOn "--" t of
    (before, after)
      | T.null after -> (before, Nothing)
      | otherwise    -> (before, Just (T.strip (T.drop 2 after)))

parseProvenance :: Text -> Either Text Provenance
parseProvenance t
  -- @gen: is checked before the generic @file:line form, so "gen" is a
  -- reserved source-file name in the canonical text (a fair trade for a
  -- self-describing stamp).
  | Just gid <- T.stripPrefix "@gen:" t =
      if T.null gid then Left ("empty generation id: " <> t) else Right (FromGeneration gid)
  | Just rest <- T.stripPrefix "@" t =
      case T.splitOn ":" rest of
        [f, n] | Just ln <- readInt n -> Right (FromSource (SourceLoc f ln))
        _ -> Left ("bad source provenance: " <> t)
  | Just rest <- T.stripPrefix "<-" t =
      case T.splitOn " via " rest of
        [idsPart, ruleTok]
          | not (T.null (T.strip ruleTok)) ->
              Right (Derived (map (DecisionId . T.strip) (T.splitOn "," idsPart)) (RuleId (T.strip ruleTok)))
        _ -> Left ("bad derived provenance: " <> t)
  | otherwise = Left ("unrecognised provenance: " <> t)

readInt :: Text -> Maybe Int
readInt s = case TR.decimal s of
  Right (n, rest) | T.null rest -> Just n
  _ -> Nothing

-- | Render a base to canonical text, one decision per line, ordered by id so
-- the output is stable and diffable.
renderBase :: Base -> Text
renderBase = T.unlines . map render . sortOn dId . toList

-- | Render a single decision to its canonical line.
render :: Decision -> Text
render d =
  T.unwords
    [ unId (dId d)
    , kindText (dKind d)
    , T.intercalate "." (unSubject (dSubject d))
    , strengthText (dStrength d)
    , quote (unAssertion (dAssertion d))
    , renderProv (dProv d)
    ]
    <> maybe "" (\r -> " -- " <> r) (dRationale d)
  where
    unId (DecisionId i) = i
    unSubject (Subject s) = s
    unAssertion (Assertion a) = a

quote :: Text -> Text
quote a = "\"" <> T.concatMap esc a <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = T.singleton c

renderProv :: Provenance -> Text
renderProv (FromSource (SourceLoc f n)) = "@" <> f <> ":" <> T.pack (show n)
renderProv (Derived ids (RuleId r)) =
  "<-" <> T.intercalate "," [i | DecisionId i <- ids] <> " via " <> r
renderProv (FromGeneration gid) = "@gen:" <> gid

kindTable :: [(Text, Kind)]
kindTable = [(kindText k, k) | k <- [minBound .. maxBound]]

strengthTable :: [(Text, Strength)]
strengthTable = [(strengthText s, s) | s <- [minBound .. maxBound]]

kindText :: Kind -> Text
kindText = T.toLower . T.pack . show

strengthText :: Strength -> Text
strengthText = T.toLower . T.pack . show
