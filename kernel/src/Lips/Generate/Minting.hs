{-# LANGUAGE OverloadedStrings #-}

-- | The pure parts of @generate@ under the inversion (crystallization plan):
-- the model mints a /language/ (a set of patterns), never the meaning of the
-- program. This replaces the reading half of commit 72ee018, where the model's
-- decisions were trusted directly. Now the model delivers grammar; the kernel
-- crystallizes the program with it, deterministically, and validates the
-- result by a full run. AI may invent grammar; only the kernel assigns meaning.
--
-- This module holds the system prompt and the parser for the model's reply.
-- The model call itself is IO and lives in the CLI. The model replies with one
-- pattern per line,
--
-- > <confidence> <id> <template> => <kind> <subject> <strength> "<assertion>"
--
-- where @\<confidence\>@ is in [0,1] and the rest is exactly the @.lang@ body
-- grammar 'Lips.Lang.Lang' stores. Low confidence flags a guess; the harness
-- refuses to admit a language it is unsure of (deduce-or-fail).
module Lips.Generate.Minting
  ( systemPrompt
  , PatternCandidate (..)
  , parsePatternCandidates
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Generate.Harness (Confidence (..))
import Lips.Lang.Lang        (parsePatternBody)
import Lips.Lang.Pattern     (Pattern)

-- | A pattern the model proposes, with the confidence it attaches to it.
data PatternCandidate = PatternCandidate
  { pcPattern    :: Pattern
  , pcConfidence :: Confidence
  }
  deriving (Eq, Show)

-- | The instruction given to the model, parameterized by the target engine's
-- vocabulary (the (kind, subject) pairs it can refine). A versioned System
-- artifact, stored in the repository and reviewable (spec section 5, layer 3).
systemPrompt :: [Text] -> Text
systemPrompt vocab = T.unlines
  [ "You crystallize a loose program into a lips LANGUAGE: a set of patterns."
  , "You do NOT translate the program's meaning. You write patterns; the kernel"
  , "applies them deterministically to derive meaning. Cover every input line."
  , ""
  , "Output ONLY pattern lines, no prose, no code fences. One pattern per"
  , "distinct line shape. Each line is:"
  , ""
  , "  <confidence> <id> <template> => <kind> <subject> <strength> \"<assertion>\""
  , ""
  , "  confidence: a number in [0,1]. 1.0 = the template obviously fits;"
  , "              below 0.7 when the shape is genuinely ambiguous."
  , "  id:         p1, p2, p3, ... unique per pattern."
  , "  template:   the loose line with VALUES replaced by <holes>. Fixed words"
  , "              carry meaning and must match literally; holes bind one token"
  , "              each (a name or value), captured verbatim."
  , "  kind/subject/strength: the decision the pattern produces."
  , "  assertion:  a string, in double quotes, holes written <name>. Every hole"
  , "              in subject or assertion MUST appear in the template."
  , ""
  , "Patterns must be orthogonal: no input line may match two of them."
  , ""
  , "Target vocabulary (map onto these subjects and kinds):"
  , T.unlines (map ("  " <>) vocab)
  , "Example input line:"
  , "  the bank drops csv files into inbox/."
  , "Example pattern:"
  , "  0.96 p1 the bank drops csv files into <loc> => fact feed.source stated \"<loc>\""
  ]

-- | Parse a model reply into pattern candidates, collecting per-line errors.
-- Blank lines, comments, and stray fences are ignored so a chatty model still
-- parses.
parsePatternCandidates :: Text -> ([Text], [PatternCandidate])
parsePatternCandidates reply =
  let ls = filter (not . ignorable) (map T.strip (T.lines reply))
   in partition (map parseLine ls)
  where
    ignorable t = T.null t || "#" `T.isPrefixOf` t || "```" `T.isPrefixOf` t
    partition results = ([e | Left e <- results], [c | Right c <- results])

parseLine :: Text -> Either Text PatternCandidate
parseLine line = do
  (confTok, r1) <- firstToken line "empty pattern line"
  (idTok, body) <- firstToken r1 ("no id after confidence: " <> line)
  conf <- parseConfidence confTok
  pat  <- either (\e -> Left (e <> " in: " <> line)) Right (parsePatternBody idTok (T.strip body))
  Right (PatternCandidate pat (Confidence conf))

firstToken :: Text -> Text -> Either Text (Text, Text)
firstToken t err =
  case T.words t of
    []      -> Left err
    (w : _) -> Right (w, T.drop (T.length w) (T.stripStart t))

parseConfidence :: Text -> Either Text Double
parseConfidence t = case TR.double t of
  Right (d, rest) | T.null rest, d >= 0, d <= 1 -> Right d
  _ -> Left ("bad confidence: " <> t)
