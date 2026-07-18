{-# LANGUAGE OverloadedStrings #-}

-- | The engine's back half as data (engine-synthesis plan): minted
-- obligation-to-mechanism rules and demands, interpreted by generic kernel
-- executors. This is what replaces hand-written engines like the former
-- @Lips.Engine.Feed@: the model mints these as decisions in the @.lang@ file;
-- 'toRule' and 'toDemand' interpret them; nothing problem-specific is ever
-- compiled into the kernel.
--
-- Body sub-grammars (stored inside a decision's assertion):
--
-- > rule:   match <kind> <subject> => <optionPath> "<rhs>" ; <optionPath> "<rhs>" ...
-- > demand: demand <subject> "<question>"
--
-- @\<rhs\>@ is a value in the closed grammar of 'Lips.Engine.Value' (string,
-- list, boolean, integer; strings may carry @\<value\>@ / @\<value.N\>@ holes
-- and @${pkgs...}@ references) -- never a Nix expression. The hole
-- @\<value\>@ fills with the matched decision's assertion text, @\<value.N\>@
-- (1-based) with its Nth whitespace-separated token. @\<value.N\>@ exists
-- because the first live minting run showed the model packing several values
-- into one assertion and unpacking them with Nix-level @splitString@
-- gymnastics; the kernel absorbs that workaround as physics (Heile Welt:
-- workarounds belong in the kernel) and the value grammar makes the
-- workaround itself unrepresentable.
--
-- Deliberate restriction: a minted rule emits only ground ('Meta') decisions,
-- so a minted rule set terminates in one refinement pass by construction --
-- no cascades. The kernel's general 'Rule' keeps supporting cascades for
-- hand-written engines; minted engines earn them when a real program needs
-- them.
module Lips.Engine.Data
  ( MapRule (..)
  , Emit (..)
  , DemandSpec (..)
  , toRule
  , toDemand
  , renderRuleBody
  , parseRuleBody
  , renderDemandBody
  , parseDemandBody
  ) where

import           Data.Text      (Text)
import qualified Data.Text      as T

import Lips.Engine.Value    (Value, fillValue, holeIndex, parseValue, renderValue)
import Lips.Kernel.Base     (Base, toList)
import Lips.Kernel.Decision
import Lips.Kernel.Demand   (Demand (..))
import Lips.Kernel.Refine   (Rule (..))

-- | One ground option assignment a rule emits: the option path and the
-- right-hand side value (closed grammar; computation unrepresentable).
data Emit = Emit
  { emPath :: [Text]
  , emRhs  :: Value
  }
  deriving (Eq, Show)

-- | A minted obligation-to-mechanism rule: matches one (kind, subject), emits
-- ground option assignments.
data MapRule = MapRule
  { mrId      :: Text
  , mrKind    :: Kind
  , mrSubject :: [Text]
  , mrEmits   :: [Emit]
  }
  deriving (Eq, Show)

-- | A minted demand: the base must contain a decision with this subject.
data DemandSpec = DemandSpec
  { dsId       :: Text
  , dsSubject  :: [Text]
  , dsQuestion :: Text
  }
  deriving (Eq, Show)

-- | Interpret a minted rule with the kernel's generic refinement machinery.
-- The emitted decisions are 'Meta' (mapped mechanisms); ids and provenance are
-- stamped by the refiner, so only subject and assertion matter here.
toRule :: MapRule -> Rule
toRule mr =
  Rule
    { rId      = RuleId (mrId mr)
    , rMatches = \d -> dKind d == mrKind mr && dSubject d == Subject (mrSubject mr)
    , rRewrite = \d -> map (emitDecision (assertionText d)) (mrEmits mr)
    }
  where
    assertionText d = case dAssertion d of Assertion a -> a
    emitDecision val e =
      Decision
        { dId        = DecisionId ""
        , dSubject   = Subject (emPath e)
        , dKind      = Meta
        , dAssertion = Assertion (fillValue (pick val) (emRhs e))
        , dStrength  = Stated
        , dProv      = FromSource (SourceLoc "" 0)
        , dRationale = Nothing
        }
    pick val "value" = val
    pick val h
      | Just n <- holeIndex h =
          case drop (n - 1) (T.words val) of
            (w : _) -> w
            -- Fail fast and loud: a silent empty string would realize a wrong
            -- module. The rewrite channel has no Either, so this is an error.
            []      -> error ("engine rule " <> T.unpack (mrId mr) <> ": <" <> T.unpack h
                                <> "> out of range for value: " <> T.unpack val)
      -- Any other hole name was rejected at parse time; loud if it slips through.
      | otherwise = error ("engine rule emit: unknown hole <" <> T.unpack h <> ">")

-- | Interpret a minted demand: satisfied when any decision has the subject.
toDemand :: DemandSpec -> Demand
toDemand ds =
  Demand
    { demId        = dsId ds
    , demQuestion  = dsQuestion ds
    , demSatisfied = hasSubject (dsSubject ds)
    }
  where
    hasSubject segs base = any ((== Subject segs) . dSubject) (toList (base :: Base))

-- Rule body: @match <kind> <subject> => <path> "<rhs>" ; <path> "<rhs>" ...@

renderRuleBody :: MapRule -> Text
renderRuleBody mr =
  "match " <> kindText (mrKind mr) <> " " <> T.intercalate "." (mrSubject mr)
    <> " => "
    <> T.intercalate " ; " (map renderEmit (mrEmits mr))
  where
    renderEmit e = T.intercalate "." (emPath e) <> " " <> quoteText (renderValue (emRhs e))

parseRuleBody :: Text -> Text -> Either Text MapRule
parseRuleBody rid body = do
  afterMatch <- note (pre <> "expected 'match '") (T.stripPrefix "match " body)
  let (matchPart, arrowPart) = T.breakOn " => " afterMatch
  emitsPart <- if T.null arrowPart then Left (pre <> "missing =>") else Right (T.drop 4 arrowPart)
  (kind, subj) <- case T.words matchPart of
    [k, s] -> (,) <$> parseKindTok pre k <*> pure (T.splitOn "." s)
    _      -> Left (pre <> "match needs '<kind> <subject>'")
  emits <- mapM (parseEmit . T.strip) (T.splitOn " ; " emitsPart)
  if null emits
    then Left (pre <> "rule emits nothing")
    else Right (MapRule rid kind subj emits)
  where
    pre = "rule " <> rid <> ": "
    parseEmit t = do
      (pathTok, rest) <- case T.words t of
        (w : _ : _) -> Right (w, T.stripStart (T.drop (T.length w) (T.stripStart t)))
        _           -> Left (pre <> "emit needs '<path> \"<rhs>\"': " <> t)
      rhsRaw <- parseQuoted pre rest
      -- Parse, don't validate: the rhs becomes a typed 'Value' here, at the
      -- only door minted engines enter; computation never gets past this line.
      rhs    <- either (\e -> Left (pre <> e)) Right (parseValue rhsRaw)
      Right (Emit (T.splitOn "." pathTok) rhs)

-- Demand body: @demand <subject> "<question>"@

renderDemandBody :: DemandSpec -> Text
renderDemandBody ds =
  "demand " <> T.intercalate "." (dsSubject ds) <> " " <> quoteText (dsQuestion ds)

parseDemandBody :: Text -> Text -> Either Text DemandSpec
parseDemandBody did body = do
  afterKw <- note (pre <> "expected 'demand '") (T.stripPrefix "demand " body)
  (subjTok, rest) <- case T.words afterKw of
    (w : _) -> Right (w, T.stripStart (T.drop (T.length w) (T.stripStart afterKw)))
    []      -> Left (pre <> "demand needs '<subject> \"<question>\"'")
  q <- parseQuoted pre rest
  Right (DemandSpec did (T.splitOn "." subjTok) q)
  where
    pre = "demand " <> did <> ": "

-- Shared small parsers (local copies; the sub-grammars are tiny and keeping
-- them self-contained beats exporting Reader internals).

parseQuoted :: Text -> Text -> Either Text Text
parseQuoted pre t = case T.uncons t of
  Just ('"', rest) -> go rest T.empty
  _                -> Left (pre <> "expected quoted string")
  where
    go s acc = case T.uncons s of
      Nothing           -> Left (pre <> "unterminated string")
      Just ('"', _)     -> Right acc
      Just ('\\', more) -> case T.uncons more of
        Just (c, more') -> go more' (T.snoc acc c)
        Nothing         -> Left (pre <> "dangling escape")
      Just (c, more)    -> go more (T.snoc acc c)

quoteText :: Text -> Text
quoteText a = "\"" <> T.concatMap esc a <> "\""
  where
    esc '"'  = "\\\""
    esc '\\' = "\\\\"
    esc c    = T.singleton c

parseKindTok :: Text -> Text -> Either Text Kind
parseKindTok pre w =
  note (pre <> "unknown kind " <> w) (lookup w [(kindText k, k) | k <- [minBound .. maxBound]])

kindText :: Kind -> Text
kindText = T.toLower . T.pack . show

note :: Text -> Maybe a -> Either Text a
note e = maybe (Left e) Right
