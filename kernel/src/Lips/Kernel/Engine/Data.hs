{-# LANGUAGE OverloadedStrings #-}

-- | The engine's back half as data (engine-synthesis plan): minted
-- obligation-to-mechanism rules and demands, interpreted by generic kernel
-- executors. This is what replaces hand-written engines like the former
-- @Lips.Kernel.Engine.Feed@: the model mints these as decisions in the @.lang@ file;
-- 'toRule' and 'toDemand' interpret them; nothing problem-specific is ever
-- compiled into the kernel.
--
-- Body sub-grammars (stored inside a decision's assertion):
--
-- > rule:   match <kind> <subject> => <optionPath> "<rhs>" ; <optionPath> "<rhs>" ...
-- > demand: demand <subject> "<question>"
--
-- @\<rhs\>@ is a value in the closed grammar of 'Lips.Kernel.Engine.Value' (string,
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
module Lips.Kernel.Engine.Data
  ( MapRule (..)
  , Emit (..)
  , DemandSpec (..)
  , toRule
  , bindSelf
  , toDemand
  , renderRuleBody
  , parseRuleBody
  , renderDemandBody
  , parseDemandBody
  , splitAttrPath
  , renderAttrPath
  ) where

import           Data.Maybe     (isJust)
import           Data.Text      (Text)
import qualified Data.Text      as T

import qualified Data.Map.Strict as Map
import           Data.Maybe      (mapMaybe)

import Lips.Kernel.Capture         (captureName, fillCaptures, fillName, matchSubject, selfName)
import Lips.Kernel.Engine.Value    (Value, bindCaptureValue, bindSelfValue, fillValue, holeIndex, parseValue, renderValue, valueCaptures)
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

-- | Bind the reserved @\<self\>@ option-path segment to the solution's
-- instance name (its file basename), so a shared language names its
-- per-instance @attrsOf@ key without baking one instance into the grammar
-- (plan 2026-07-22). The model emits @services.restic.backups.\<self\>.paths@;
-- the option schema admits @\<self\>@ only where it declares a @"*"@ wildcard,
-- and each solution fills it with its own name. The same token also resolves
-- inside a rhs value (a @\<self\>@ string piece, a @${artifact.\<self\>}@
-- reference) via 'bindSelfValue', so a rule can name the program's own build
-- or app; segments and values that do not mention @\<self\>@ are untouched.
bindSelf :: Text -> MapRule -> MapRule
bindSelf name mr = mr { mrEmits = map bindEmit (mrEmits mr) }
  where
    bindEmit e = e { emPath = map seg (emPath e), emRhs = bindSelfValue name (emRhs e) }
    -- Occurrence fill over the shared name grammar, so a COMPOSED segment
    -- (artifact.<self>-core: a second build beside the instance's own) resolves
    -- like a whole <self>. A <capture> in the same segment is left standing for
    -- 'fillSeg' at match time; the two passes share the helper, not the map.
    seg = fillName (\t -> if t == selfName then Just name else Nothing)

-- | Interpret a minted rule with the kernel's generic refinement machinery.
-- The emitted decisions are 'Meta' (mapped mechanisms); ids and provenance are
-- stamped by the refiner, so only subject and assertion matter here.
-- A rule subject may name a value-keyed FAMILY: a @<name>@ segment is a
-- capture that binds any concrete segment (e.g. @route.<path>.status@ matches
-- @route.hello.status@). The captured key then fills the matching @<name>@
-- segment of an emit path, so N sibling decisions fan out to N distinct option
-- slots keyed by their own value, riding Nix's native attrsOf merge -- the
-- per-item analogue of the language-level @<self>@ instance key.
toRule :: MapRule -> Rule
toRule mr =
  Rule
    { rId      = RuleId (mrId mr)
    , rMatches = \d -> dKind d == mrKind mr && isJust (matchSubject (mrSubject mr) (subjSegs d))
    , rRewrite = \d -> case matchSubject (mrSubject mr) (subjSegs d) of
        Nothing   -> Right []   -- unreachable: 'rMatches' gates the rewrite
        Just caps -> traverse (emitDecision caps (assertionText d)) (mrEmits mr)
    }
  where
    subjSegs d = case dSubject d of Subject segs -> segs
    assertionText d = case dAssertion d of Assertion a -> a
    emitDecision caps val e = do
      -- A program value that does not fit this emit (a missing @<value.N>@
      -- token, a wrong-typed hole) is a 'Left' the refiner turns into a loud
      -- 'RewriteFailed', not a crash: 'print' is deterministic and edited
      -- programs must fail through the error channel, never by exception.
      p <- traverse (fillSeg caps) (emPath e)
      -- Captures reach a value two ways: as an artifact-ref NAME (a structural
      -- pass, like <self>) and as a string hole (through 'pick' below).
      a <- fillValue (pick caps val) (bindCaptureValue caps (emRhs e))
      Right Decision
        { dId        = DecisionId ""
        , dSubject   = Subject p
        , dKind      = Meta
        , dAssertion = Assertion a
        , dStrength  = Stated
        , dProv      = FromSource (SourceLoc "" 0)
        , dRationale = Nothing
        }
    -- Fill the captured key into an emit-path segment (whole or embedded); a
    -- shared primitive so rules, expects, and demands resolve captures alike.
    fillSeg caps seg = either (\r -> Left ("engine rule " <> mrId mr <> ": emit path " <> r))
                              Right (fillCaptures caps seg)
    pick _ val "value" = Right val
    pick caps val h
      | Just n <- holeIndex h =
          case drop (n - 1) (T.words val) of
            (w : _) -> Right w
            []      -> Left ("engine rule " <> mrId mr <> ": <" <> h
                                <> "> out of range for value: " <> val)
      -- Otherwise the hole names a capture the subject bound, so the rule may
      -- carry the key itself into a value (an artifact's args.name, a wrapper's
      -- text) and not only into an option path.
      | Just v <- Map.lookup h caps = Right v
      | otherwise = Left ("engine rule " <> mrId mr <> ": <" <> h
                            <> "> is neither <value>/<value.N> nor a capture"
                            <> " bound by the subject")

-- | Interpret a minted demand: satisfied when any decision matches the subject.
-- 'matchSubject' means a family demand (@route.<path>.status@) is met by any
-- concrete route, while a plain subject still needs an exact match.
toDemand :: DemandSpec -> Demand
toDemand ds =
  Demand
    { demId        = dsId ds
    , demQuestion  = dsQuestion ds
    , demSatisfied = hasSubject (dsSubject ds)
    }
  where
    hasSubject segs base =
      any (isJust . matchSubject segs . subjOf) (toList (base :: Base))
    subjOf d = case dSubject d of Subject xs -> xs

-- Rule body: @match <kind> <subject> => <path> "<rhs>" ; <path> "<rhs>" ...@

renderRuleBody :: MapRule -> Text
renderRuleBody mr =
  "match " <> kindText (mrKind mr) <> " " <> renderAttrPath (mrSubject mr)
    <> " => "
    <> T.intercalate " ; " (map renderEmit (mrEmits mr))
  where
    renderEmit e = renderAttrPath (emPath e) <> " " <> quoteText (renderValue (emRhs e))

parseRuleBody :: Text -> Text -> Either Text MapRule
parseRuleBody rid body = do
  afterMatch <- note (pre <> "expected 'match '") (T.stripPrefix "match " body)
  let (matchPart, arrowPart) = T.breakOn " => " afterMatch
  emitsPart <- if T.null arrowPart then Left (pre <> "missing =>") else Right (T.drop 4 arrowPart)
  (kind, subj) <- case T.words matchPart of
    [k, s] -> (,) <$> parseKindTok pre k <*> splitAttrPath s
    _      -> Left (pre <> "match needs '<kind> <subject>'")
  emits <- mapM (parseEmit . T.strip) (T.splitOn " ; " emitsPart)
  if null emits
    then Left (pre <> "rule emits nothing")
    else do
      -- A value hole is <value>/<value.N> or a CAPTURE this subject binds. The
      -- subject is in hand right here, so an unbound name fails at the door
      -- every minted engine enters, not later at refine on an author's machine.
      let bound = mapMaybe captureName subj
      case [ nm | e <- emits, nm <- valueCaptures (emRhs e), nm `notElem` bound ] of
        (nm : _) -> Left (pre <> "<" <> nm <> "> is neither <value>/<value.N> nor a"
                            <> " capture bound by the subject " <> renderAttrPath subj)
        []       -> Right (MapRule rid kind subj emits)
  where
    pre = "rule " <> rid <> ": "
    parseEmit t = do
      (pathTok, rest0) <- case T.words t of
        (w : _ : _) -> Right (w, T.stripStart (T.drop (T.length w) (T.stripStart t)))
        _           -> Left (pre <> "emit needs '<path> <rhs>': " <> t)
      let rest = T.stripStart rest0
      -- Parse, don't validate: the rhs becomes a typed 'Value' here, at the
      -- only door minted engines enter; computation never gets past this line.
      -- Accept either a transport-quoted rhs (the canonical stored form, used
      -- for strings and lists) or a BARE value (null, a path, a number, a
      -- bool, a typed hole) as models naturally write them. The renderer
      -- always emits the quoted form, so stored engines stay canonical.
      rhs <- case T.uncons rest of
        Just ('"', _) -> do
          inner <- parseQuoted pre rest
          either (\e -> Left (pre <> e)) Right (parseValue inner)
        _ -> either (\e -> Left (pre <> e)) Right (parseValue rest)
      Emit <$> splitAttrPath pathTok <*> pure rhs

-- Demand body: @demand <subject> "<question>"@

renderDemandBody :: DemandSpec -> Text
renderDemandBody ds =
  "demand " <> renderAttrPath (dsSubject ds) <> " " <> quoteText (dsQuestion ds)

parseDemandBody :: Text -> Text -> Either Text DemandSpec
parseDemandBody did body = do
  afterKw <- note (pre <> "expected 'demand '") (T.stripPrefix "demand " body)
  (subjTok, rest) <- case T.words afterKw of
    (w : _) -> Right (w, T.stripStart (T.drop (T.length w) (T.stripStart afterKw)))
    []      -> Left (pre <> "demand needs '<subject> \"<question>\"'")
  q <- parseQuoted pre rest
  DemandSpec did <$> splitAttrPath subjTok <*> pure q
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

-- | Split a dotted attribute path -- a rule emit path or an expect option path
-- -- into segments, tolerating the Nix-attr-path quoting a model may write. A
-- segment wrapped in @"..."@ is taken literally (no split on a dot inside) and
-- the surrounding quotes are stripped, so @locations."/".proxyPass@ and
-- @locations./.proxyPass@ parse to the SAME segment @/@. A backslash escapes
-- the next char (@\"@, @\\@, @\.@), mirroring the base 'splitSubject'; an
-- unterminated quote fails loud.
--
-- Why normalize here, not at render: the canonical stored form writes keys
-- BARE (the kernel quotes on realize via 'quoteSeg'), so a bare segment
-- round-trips unchanged and every existing engine is byte-identical. The model
-- is one-shot and may write a quoted key in either the rule or the expect (or
-- split across them); normalizing at the only door minted engines enter keeps
-- the two sides agreeing on the key without a prompt plea. This is the engine
-- analogue of the base subject split ('Lips.Kernel.Reader.splitSubject'):
-- both are quote/escape-aware, so a path segment is never shredded by a dot.
splitAttrPath :: Text -> Either Text [Text]
splitAttrPath t0 = go (T.stripStart t0) T.empty []
  where
    pre = "bad attribute path " <> t0 <> ": "
    -- Outside a quoted span: '.' separates; '\' escapes the next char;
    -- '"' opens a quoted span (its quote is not part of the segment).
    go t cur acc = case T.uncons t of
      Nothing            -> Right (revcons cur acc)
      Just ('.', r)      -> go r T.empty (cur : acc)
      Just ('"', r)      -> inQuote r cur acc
      Just ('\\', r)    -> case T.uncons r of
        Just (c, r') -> go r' (T.snoc cur c) acc
        Nothing      -> Left (pre <> "dangling escape")
      Just (c, r)        -> go r (T.snoc cur c) acc
    -- Inside a quoted span: '"' closes; '\' escapes the next char (so a key
    -- may contain a quote or a dot); a '.' is literal, so a dotted key stays
    -- one segment.
    inQuote t cur acc = case T.uncons t of
      Nothing           -> Left (pre <> "unterminated quote")
      Just ('"', r)     -> go r cur acc
      Just ('\\', r)   -> case T.uncons r of
        Just (c, r') -> inQuote r' (T.snoc cur c) acc
        Nothing      -> Left (pre <> "dangling escape in quotes")
      Just (c, r)       -> inQuote r (T.snoc cur c) acc
    revcons cur acc = reverse (cur : acc)

-- | Render a dotted attribute path -- the inverse of 'splitAttrPath'. Each
-- segment is escaped so a literal @.@ or @\@ in it cannot be mistaken for a
-- separator or an escape, mirroring the base 'Lips.Kernel.Reader.joinSubject'
-- (so the engine layer and the base layer share one canonical path form).
-- A segment without @.@ or @\@ (every identifier and @<self>\/@<name>@
-- placeholder) renders unchanged, so every existing engine is byte-identical.
renderAttrPath :: [Text] -> Text
renderAttrPath = T.intercalate "." . map (T.concatMap esc)
  where
    esc '.'  = "\\."
    esc '\\' = "\\\\"
    esc c    = T.singleton c

parseKindTok :: Text -> Text -> Either Text Kind
parseKindTok pre w =
  note (pre <> "unknown kind " <> w) (lookup w [(kindText k, k) | k <- [minBound .. maxBound]])

kindText :: Kind -> Text
kindText = T.toLower . T.pack . show

note :: Text -> Maybe a -> Either Text a
note e = maybe (Left e) Right
