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
  ) where

import           Data.Bits          (shiftR, xor)
import qualified Data.ByteString    as BS
import           Data.Text          (Text)
import qualified Data.Text          as T
import           Data.Text.Encoding (encodeUtf8)
import           Data.Word          (Word64)

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
-- The tool transcript sits between the corpus and the reply because that is
-- where it belongs causally: what the mint was told is an input, like the
-- corpus, and the reply is what it made of both. Being inside the record, it is
-- inside 'genId', so an engine minted from a different answer is a different
-- generation event even when prompt and corpus are identical (invariant 6).
record :: Text -> Target -> Double -> Text -> Text -> Text -> Text -> Text
record model target confidence sysPrompt program transcript reply = T.unlines
  [ "model: " <> model
  , "target: " <> targetSlug target
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
genId = hex . BS.foldl' step offset . encodeUtf8
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
