{-# LANGUAGE OverloadedStrings #-}

-- | The generation record and its identity (spec section 5: the generation
-- event is pinned -- model, prompt, inputs, raw reply -- and committed with
-- the engine; record = provenance).
--
-- 'genId' names a record by content: every decision in a minted @.lang@ is
-- stamped @\@gen:\<genId record\>@, so any engine line points at the exact
-- generation event that produced it, and the link is mechanically checkable
-- (re-hash the @.generation@ file, compare the stamp). The hash is FNV-1a
-- 64-bit: an /identifier/, not a security boundary -- the record sits in the
-- same repository as the stamp, so tampering is a git problem, not a
-- cryptography problem. Pure Haskell keeps the kernel free of external
-- hashing dependencies.
module Lips.Generate.Record
  ( record
  , genId
  , hashBytes
  , corpusText
  , recordedProgram
  ) where

import           Data.Bits          (shiftR, xor)
import qualified Data.ByteString    as BS
import           Data.List          (dropWhileEnd)
import           Data.Text          (Text)
import qualified Data.Text          as T
import           Data.Text.Encoding (encodeUtf8)
import           Data.Word          (Word64)

import           System.FilePath    (takeFileName)

import           Lips.Nix.Target    (Target, targetSlug)

-- | The auditable record of a generation event: everything the model saw and
-- said, self-contained (the system prompt is embedded, not referenced, so the
-- record stays honest even after the prompt artifact evolves). Stored as
-- @\<file\>.generation@, committed beside the engine.
--
-- The confidence threshold is part of the event: it co-determines what was
-- admitted (deduce-or-fail), so a record that omitted it would not pin the
-- event. It therefore also enters 'genId', so re-running with a different
-- threshold yields a different id.
-- The target world co-determines what the mint produced (the option namespace
-- it aimed at and the schema it was grounded against), so it is part of the
-- event and enters 'genId': a re-mint targeting a different world yields a
-- different id, so every engine line's @gen stamp pins the world it was minted
-- for.
-- The schema pin is the LOCKED flakeref (as @nix flake metadata@ reports it)
-- whose option document grounded the mint, or @options-json:\<hash\>@ when a
-- caller supplied the document directly. It co-determines the engine: an option
-- present in one nixpkgs and absent in the next decides whether a rule was
-- admitted at all, so a record omitting it would leave a mint input
-- unaccounted for (invariant 6). It enters 'genId' like every other input.
-- The tool transcript sits between the corpus and the reply because that is
-- where it belongs causally: what the mint was told is an input, like the
-- corpus, and the reply is what it made of both. Being inside the record, it is
-- inside 'genId', so an engine minted from a different answer is a different
-- generation event even when prompt and corpus are identical (invariant 6).
-- The thinking level is an input like the model: it changes what the mint
-- produces, so a record omitting it would not pin the event. lips always passes
-- it explicitly, so nothing ambient can steer a mint unrecorded.
record :: Text -> Target -> Text -> Text -> Double -> Text -> Text -> Text -> Text -> Text
record model target schema thinking confidence sysPrompt program transcript reply = T.unlines
  [ "model: " <> model
  , "target: " <> targetSlug target
  , "schema: " <> schema
  , "thinking: " <> thinking
  , "confidence-threshold: " <> T.pack (show confidence)
  , "--- system prompt ---", sysPrompt
  , "--- program (input) ---", program
  , "--- tool transcript ---", transcript
  , "--- raw reply ---", reply
  ]

-- | Content identity of a record: FNV-1a 64-bit over UTF-8, 16 hex digits.
-- Deterministic, dependency-free; collision odds are negligible for its job
-- (naming generation events within one repository).
genId :: Text -> Text
genId = hashBytes . encodeUtf8

-- | The same content id over raw bytes, for the one input that is not text lips
-- wrote: a caller-supplied options document, which the record pins by content
-- because it has no flakeref to name ('ensureOptionSchema'). One hash function
-- serves the whole provenance story.
hashBytes :: BS.ByteString -> Text
hashBytes = hex . BS.foldl' step offset
  where
    offset = 14695981039346656037 :: Word64
    prime  = 1099511628211 :: Word64
    step h b = (h `xor` fromIntegral b) * prime
    hex = T.pack . go 16 []
      where
        go :: Int -> [Char] -> Word64 -> [Char]
        go 0 acc _ = acc
        go n acc w = go (n - 1) (digit (fromIntegral (w `mod` 16)) : acc) (w `shiftR` 4)
        digit d = if d < 10 then toEnum (fromEnum '0' + d) else toEnum (fromEnum 'a' + d - 10)

-- | The corpus the mint reads: every program of one language, each framed by its
-- file name. The mint sees them all at once so the grammar generalizes across
-- them, and the same text is recorded as the generation's input -- which makes it
-- the one offline witness of what each program SAID when its language (and any
-- artifact source) was minted.
corpusText :: [(FilePath, Text)] -> Text
corpusText progs = T.intercalate "\n"
  [ header f <> "\n" <> t | (f, t) <- progs ]

header :: FilePath -> Text
header f = "=== program " <> T.pack (takeFileName f) <> " ==="

-- | Read one program's text back out of a committed record: the inverse of
-- 'corpusText' over the record's program block. 'Nothing' when this record holds
-- no section for that file (an older record, or a program added after the mint),
-- which the caller treats as "nothing to compare" rather than as a failure.
recordedProgram :: FilePath -> Text -> Maybe Text
recordedProgram file rec =
  case break (== header file) (dropWhile (/= "--- program (input) ---") (T.lines rec)) of
    -- The framing separates sections with a blank line, which is not part of the
    -- program (and is ignored by crystallize anyway); drop it so the text read
    -- back equals the text put in.
    (_, _ : rest) -> Just (T.unlines (dropWhileEnd T.null (takeWhile ours rest)))
    _             -> Nothing
  where
    -- The section ends at the next program header or at the next record block.
    ours l = not ("=== program " `T.isPrefixOf` l) && not ("--- " `T.isPrefixOf` l)
