{-# LANGUAGE OverloadedStrings #-}

-- | The reading half of @generate@ (spec v2, section 5): turning a human's
-- loose program text into a canonical decision base. The model proposes, the
-- deterministic harness disposes.
--
-- This module holds the /pure/ parts: the system prompt that instructs the
-- model, and the parser that turns the model's reply into 'Candidate's. The
-- model call itself is IO and lives in the CLI (the imperative shell). The
-- model must reply with one candidate per line,
--
-- > <confidence> <canonical-decision-line>
--
-- where @<confidence>@ is a number in [0,1] and the rest is exactly the
-- canonical form 'Lips.Kernel.Reader' parses. Low confidence is how the model
-- flags a guess; the harness demotes those to open questions.
module Lips.Generate.Reading
  ( systemPrompt
  , parseCandidates
  ) where

import           Data.Text       (Text)
import qualified Data.Text       as T
import qualified Data.Text.Read  as TR

import Lips.Generate.Harness (Candidate (..), Confidence (..))
import Lips.Kernel.Reader    (readDecision)

-- | The instruction given to the model. It is a versioned System artifact
-- (spec section 5, layer 3), not an incantation: it is stored here, in the
-- repository, and changes to it are reviewable.
systemPrompt :: Text
systemPrompt = T.unlines
  [ "You convert a loose program into lips canonical decision form."
  , "A program is a set of decisions. Re-express every line of the input as"
  , "one decision line. Output ONLY decision lines, no prose, no code fences."
  , ""
  , "Each output line is:  <confidence> <id> <kind> <subject> <strength> \"<assertion>\" @program:<line>"
  , ""
  , "  confidence: a number in [0,1]. 1.0 = a direct restatement; lower when"
  , "              you infer the subject or kind; below 0.7 when genuinely"
  , "              ambiguous (the harness turns those into questions)."
  , "  id:         d1, d2, d3, ... unique per line."
  , "  kind:       one of concept fact oblige forbid allow invariant view assume steer glue meta."
  , "  subject:    a dotted path naming what the decision is about (feed.source, account.balance)."
  , "  strength:   stated for anything a human wrote."
  , "  assertion:  the meaning, in double quotes (escape \\\" and \\\\)."
  , "  @program:<line>: the 1-based input line this came from."
  , ""
  , "Example input:"
  , "  the bank drops csv files into inbox/, hourly."
  , "  every bank row becomes a transaction."
  , "Example output:"
  , "  0.96 d1 fact feed.source stated \"inbox/\" @program:1"
  , "  0.9 d2 fact feed.cadence stated \"hourly\" @program:1"
  , "  0.92 d3 oblige feed.ingest stated \"every bank row becomes a transaction\" @program:2"
  ]

-- | Parse a model reply into candidates, collecting per-line errors. Blank
-- lines, comment lines, and stray markdown fences are ignored so a slightly
-- chatty model still parses.
parseCandidates :: Text -> ([Text], [Candidate])
parseCandidates reply =
  let ls = filter (not . ignorable) (map T.strip (T.lines reply))
      results = map parseCandidateLine ls
   in ([e | Left e <- results], [c | Right c <- results])
  where
    ignorable t = T.null t || "#" `T.isPrefixOf` t || "```" `T.isPrefixOf` t

-- | One @\<confidence\> \<canonical line\>@ candidate.
parseCandidateLine :: Text -> Either Text Candidate
parseCandidateLine line =
  case T.break (== ' ') (T.stripStart line) of
    (confTok, rest)
      | T.null (T.strip rest) -> Left ("no decision after confidence: " <> line)
      | otherwise -> do
          conf <- parseConfidence confTok
          dec  <- either (Left . prefixErr) Right (readDecision (T.strip rest))
          Right (Candidate dec (Confidence conf))
  where
    prefixErr e = "canonical parse failed: " <> T.pack (show e) <> " in: " <> line

parseConfidence :: Text -> Either Text Double
parseConfidence t = case TR.double t of
  Right (d, rest) | T.null rest, d >= 0, d <= 1 -> Right d
  _ -> Left ("bad confidence: " <> t)
