{-# LANGUAGE OverloadedStrings #-}

-- | The pure parts of @generate@ (crystallization + engine-synthesis plans):
-- the model mints a whole /engine/ -- patterns (the language), rules (the
-- mechanisms), demands (completeness) -- and never the meaning of the program.
-- The kernel crystallizes the program with the minted engine and validates by
-- a full run; nothing the model says becomes meaning except through
-- deterministic template matching.
--
-- With the back half minted too, no vocabulary hint remains: the model invents
-- the intermediate subjects itself, and closure is /checked/, not trusted --
-- an unmapped decision, an unmet demand, an uncovered line, or invalid Nix
-- each fails the validation run.
--
-- This module holds the system prompt and the parser for the model's reply.
-- The model call itself is IO and lives in the CLI. The model replies with one
-- confidence-prefixed item per line; the item body distinguishes the three
-- forms (pattern, @match@ rule, @demand@).
module Lips.Generate.Minting
  ( systemPrompt
  , EngineItem (..)
  , ItemCandidate (..)
  , parseEngineCandidates
  , assemble
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Engine.Data      (DemandSpec, MapRule, parseDemandBody, parseRuleBody)
import Lips.Generate.Harness (Confidence (..))
import Lips.Lang.Lang        (EngineData (..), parsePatternBody)
import Lips.Lang.Pattern     (Pattern)

-- | One minted engine item.
data EngineItem
  = ItemPattern Pattern
  | ItemRule MapRule
  | ItemDemand DemandSpec
  deriving (Eq, Show)

-- | An item the model proposes, with the confidence it attaches to it.
data ItemCandidate = ItemCandidate
  { icItem       :: EngineItem
  , icConfidence :: Confidence
  }
  deriving (Eq, Show)

-- | The instruction given to the model. A versioned System artifact, stored in
-- the repository and reviewable (spec section 5, layer 3).
systemPrompt :: Text
systemPrompt = T.unlines
  [ "You crystallize a loose program into a lips ENGINE: patterns (the"
  , "language), rules (the mechanisms), and demands (completeness). You never"
  , "state the program's meaning; the kernel derives it deterministically by"
  , "applying your patterns to the program text."
  , ""
  , "Output ONLY lines of these three forms, no prose, no code fences:"
  , ""
  , "  <confidence> <id> <template> => <kind> <subject> <strength> \"<assertion>\""
  , "  <confidence> <id> match <kind> <subject> => <option.path> \"<rhs>\" ; <option.path> \"<rhs>\""
  , "  <confidence> <id> demand <subject> \"<question>\""
  , ""
  , "confidence: a number in [0,1]; below 0.7 means unsure, and the build will"
  , "refuse the engine (that is correct behavior, not failure)."
  , ""
  , "PATTERNS (ids p1, p2, ...): one per distinct line shape; together they"
  , "must cover every input line. template = the loose line with VALUES"
  , "replaced by <holes>; fixed words match literally (case-insensitive)."
  , "Each hole binds exactly one token, captured verbatim. kind: one of"
  , "concept fact oblige forbid allow invariant view assume steer glue meta."
  , "strength: stated. subject: invent a dotted vocabulary for this problem"
  , "(e.g. backup.source). Every hole used in the subject or assertion MUST"
  , "appear in the template. Patterns must be orthogonal: no input line may"
  , "match two of them."
  , ""
  , "RULES (ids r1, r2, ...): map EVERY subject your patterns produce to"
  , "NixOS option assignments; any decision no rule maps fails the build."
  , "<rhs> is a VALUE, not a Nix expression -- the kernel rejects computation."
  , "Allowed forms only: a quoted string, a list [ ... ] of values, true,"
  , "false, or an integer. Inside strings only two things beyond literal text"
  , "parse: the holes <value> (the matched decision's assertion) / <value.N>"
  , "(its Nth whitespace-separated token, 1-based; use it when a pattern's"
  , "assertion joins several holes) and ${pkgs.<name>} package references."
  , "No functions, no splitString, no other ${...}. Quote Nix strings:"
  , "\"\\\"<value>\\\"\". Realize work as systemd services and timers or other"
  , "NixOS options."
  , ""
  , "DEMANDS (ids q1, q2, ...): what any program in this language must state,"
  , "as a subject plus the question to ask when it is missing."
  , ""
  , "The kernel verifies: every line crystallizes, every decision is mapped,"
  , "every demand is met, and the result parses as a NixOS module."
  , ""
  , "Example input line:"
  , "  the bank drops csv files into inbox/."
  , "Example output lines:"
  , "  0.96 p1 the bank drops csv files into <loc> => fact feed.source stated \"<loc>\""
  , "  0.95 r1 match fact feed.source => systemd.services.ingest.environment.INBOX \"\\\"<value>\\\"\""
  , "  0.9 q1 demand feed.source \"where do the files arrive?\""
  ]

-- | Parse a model reply into item candidates, collecting per-line errors.
-- Blank lines, comments, and stray fences are ignored so a chatty model still
-- parses.
parseEngineCandidates :: Text -> ([Text], [ItemCandidate])
parseEngineCandidates reply =
  let ls = filter (not . ignorable) (map T.strip (T.lines reply))
      results = map parseLine ls
   in ([e | Left e <- results], [c | Right c <- results])
  where
    ignorable t = T.null t || "#" `T.isPrefixOf` t || "```" `T.isPrefixOf` t

-- | Group parsed items into an engine.
assemble :: [EngineItem] -> EngineData
assemble items =
  EngineData
    { edPatterns = [p | ItemPattern p <- items]
    , edRules    = [r | ItemRule r <- items]
    , edDemands  = [q | ItemDemand q <- items]
    }

parseLine :: Text -> Either Text ItemCandidate
parseLine line = do
  (confTok, r1) <- firstToken line "empty item line"
  (idTok, body0) <- firstToken r1 ("no id after confidence: " <> line)
  conf <- parseConfidence confTok
  let body = T.strip body0
  item <-
    if "match " `T.isPrefixOf` body
      then ItemRule <$> located (parseRuleBody idTok body)
      else if "demand " `T.isPrefixOf` body
        then ItemDemand <$> located (parseDemandBody idTok body)
        else ItemPattern <$> located (parsePatternBody idTok body)
  Right (ItemCandidate item (Confidence conf))
  where
    located = either (\e -> Left (e <> " in: " <> line)) Right

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseConfidence :: Text -> Either Text Double
parseConfidence t = case TR.double t of
  Right (d, rest) | T.null rest, d >= 0, d <= 1 -> Right d
  _ -> Left ("bad confidence: " <> t)
