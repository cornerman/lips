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
  , worldHash
  , genId
  , hashBytes
  , corpusText
  , recordedProgram
  , recordedPrograms
  , recordedSchema
  , recordedWorld
  , recordedWorldPin
  , StampFault (..)
  , stampFaults
  , renderStampFault
  ) where

import           Data.Bits          (shiftR, xor)
import qualified Data.ByteString    as BS
import           Data.List          (dropWhileEnd)
import           Data.Maybe         (isJust, listToMaybe)
import           Data.Text          (Text)
import qualified Data.Text          as T
import           Data.Text.Encoding (encodeUtf8)
import           Data.Word          (Word64)

import           System.FilePath    (takeFileName)

import           Lips.Kernel.Decision (Decision (..), Provenance (..))
import           Lips.Kernel.Reader   (readDecision)
import           Lips.World           (World (..))

-- | The auditable record of a generation event: everything the model saw and
-- said, self-contained (the system prompt is embedded, not referenced, so the
-- record stays honest even after the prompt artifact evolves). Stored as
-- @\<file\>.generation@, committed beside the engine.
--
-- The confidence threshold is part of the event: it co-determines what was
-- admitted (deduce-or-fail), so a record that omitted it would not pin the
-- event. It therefore also enters 'genId', so re-running with a different
-- threshold yields a different id.
-- The world co-determines what the mint produced (the option namespace it aimed
-- at and the schema it was grounded against), so it is part of the event and
-- enters 'genId': a re-mint into a different world yields a different id, so
-- every engine line's @gen stamp pins the world it was minted for. Recorded as
-- NAME plus the content hash of the world file beside the engine, because a
-- world is data now: the name alone would not say which version of it ran, and
-- the hash is what compile re-checks the committed copy against.
-- The format line pins the record's own shape, so a lips that learns a new
-- record field can tell a record it fully understands from one it does not.
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
record :: Text -> [(Text, Text, Text)] -> Text -> Double -> Text -> Text -> Text -> Text -> Text
record model worlds thinking confidence sysPrompt program transcript reply = T.unlines $
  [ "format: 1"
  , "model: " <> model ]
  ++ concat [ [ "world: " <> n <> " " <> h, "schema: " <> s ] | (n, h, s) <- worlds ]
  ++
  [ "thinking: " <> thinking
  , "confidence-threshold: " <> T.pack (show confidence)
  , "--- system prompt ---", sysPrompt
  , "--- program (input) ---", program
  , "--- tool transcript ---", transcript
  , "--- raw reply ---", reply
  ]

-- | A world file's content id: what a record pins it by, and what @compile@
-- re-checks the committed copy against. The same hash the record's own id uses.
worldHash :: World -> Text
worldHash = hashBytes . encodeUtf8 . wRaw

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

-- | One engine line whose stamp does not name the generation record beside it.
-- The line number is the @.lang@'s own, so a report points where the fix goes.
data StampFault
  = -- | The line names an event none of the language's records hashes to: the
    --   stamp it carries, then the ids that ARE available.
    StaleStamp Int Text [Text]
  | -- | The line carries no stamp, while records sit beside it.
    Unstamped Int [Text]
  | -- | The line names an event, and there is no record at all to name.
    OrphanStamp Int Text
  deriving (Eq, Show)

-- | Invariant 6, checked: every line of an engine must be stamped with the id
-- its own @.generation@ hashes to. Deterministic, offline and domain-blind --
-- it re-runs 'genId' over the record's bytes and compares.
--
-- SEVERAL records, because a language is minted once per world: the shared
-- grammar's lines name whichever mint wrote them, and each world's rules name
-- their own. A line is sound when it names ONE of them, which is as strict as
-- the single-record rule was -- every id still has to come from a record that
-- re-hashes here.
--
-- The list may be empty, because an engine may legitimately have no record: a
-- draft lips materializes to judge, or a hand-written one. Then the rule
-- inverts rather than relaxing -- no line may claim a generation, since a stamp
-- naming a record that is not there vouches for nothing, which is the state the
-- re-hash exists to make impossible.
--
-- Lines that are not decisions at all (blank, comment, malformed) are skipped:
-- 'Lips.Kernel.Lang.Store.readLang' is the door that refuses those, and one
-- defect should be reported by one gate.
stampFaults :: [Text] -> Text -> [StampFault]
stampFaults recs langText =
  [ f
  | (n, t) <- zip [1 ..] (T.lines langText)
  , Right d <- [readDecision (T.strip t)]
  , f <- fault n (stampOf d)
  ]
  where
    stampOf d = case dProv d of
      FromGeneration g -> Just g
      _                -> Nothing
    ids = map genId recs
    fault n found = case (ids, found) of
      ([], Just g)                      -> [OrphanStamp n g]
      ([], Nothing)                     -> []
      (_,  Just g) | g `notElem` ids    -> [StaleStamp n g ids]
      (_,  Nothing)                     -> [Unstamped n ids]
      _                                 -> []

-- | One stamp fault in the words its reader needs: which line, what it claims,
-- and what the record actually says.
renderStampFault :: StampFault -> Text
renderStampFault (StaleStamp n g want) =
  "line " <> T.pack (show n) <> " is stamped @gen:" <> g
    <> ", but the records beside it hash to " <> T.intercalate ", " want
renderStampFault (Unstamped n want) =
  "line " <> T.pack (show n) <> " carries no @gen: stamp, so nothing says which \
  \generation wrote it (the records beside it hash to "
    <> T.intercalate ", " want <> ")"
renderStampFault (OrphanStamp n g) =
  "line " <> T.pack (show n) <> " is stamped @gen:" <> g
    <> ", and there is no generation record beside it to name"

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

-- | The option schema a committed record was minted against: the locked
-- flakeref, or @options-json:\<hash\>@ for a supplied document. 'Nothing' for a
-- record written before the pin existed, which is a fact about that record and
-- not a failure.
--
-- Read so a re-mint can SAY when it re-grounds. The pin is deliberately not
-- sticky (a re-mint is the moment you want fresh grounding, and replay is
-- impossible anyway, since the model is nondeterministic), which leaves exactly
-- one hole: nobody was told. Printing the two pins closes it without new state.
recordedSchema :: Text -> Maybe Text
recordedSchema rec = case [ T.strip rest | l <- T.lines rec, Just rest <- [T.stripPrefix "schema:" l] ] of
  (p : _) | not (T.null p) -> Just p
  _                        -> Nothing

-- | Which world a record names, and the world file it pins: @(name, hash)@.
-- Pure, so the precedence is testable without a filesystem.
--
-- The @format:@ header decides how the record is read, which is what a version
-- is FOR: format 1 pins the world by name and content hash, and a format-1
-- record without that line is a defect. A record with no format header is
-- format 0 (written before worlds were data): it names a world by @target:@
-- slug, or none at all -- and "none" meant nixos to the lips that wrote it, so
-- that is what it still means. Not a fallback: a committed record is SEALED (a
-- byte changed invalidates every @gen stamp it names), so this is the only way
-- its own words can be read. The world FILE beside the engine is required
-- either way; only the hash check needs a pin to check against.
-- | The pin one world carries in a record that may cover several: its declared
-- name and the hash of the world file it was minted against. 'Nothing' when the
-- record does not name that world at all, which is how a reader tells a joint
-- record apart from another world's.
--
-- One @world:@ line per world, each followed by that world's @schema:@ pin, so
-- a joint mint records every physics it aimed at. A record covering ONE world
-- renders exactly the bytes it always did, which matters because a record is
-- sealed: its hash stamps every line of the engine beside it.
recordedWorldPin :: Text -> Text -> Maybe (Text, Maybe Text)
recordedWorldPin src world = listToMaybe
  [ (n, Just h)
  | l <- T.lines src, Just rest <- [T.stripPrefix "world:" l]
  , (n : h : _) <- [T.words (T.strip rest)], n == world ]

recordedWorld :: Text -> Either Text (Text, Maybe Text)
recordedWorld src
  | isJust (firstOf "format:") = case pinned of
      Just (n, h) -> Right (n, Just h)
      Nothing     -> Left "the record states a format but names no world, so nothing \
                          \says which physics this engine was minted into"
  | otherwise = Right (maybe "nixos" id legacy, Nothing)
  where
    firstOf k = listToMaybe [ T.strip rest | l <- T.lines src, Just rest <- [T.stripPrefix k l] ]
    pinned = do
      v <- firstOf "world:"
      case T.words v of
        (n : h : _) -> Just (n, h)
        _           -> Nothing
    legacy = do
      v <- firstOf "target:"
      if T.null v then Nothing else Just v

-- | Read one program's text back out of a committed record: the inverse of
-- 'corpusText' over the record's program block. 'Nothing' when this record holds
-- no section for that file (an older record, or a program added after the mint),
-- which the caller treats as "nothing to compare" rather than as a failure.
recordedProgram :: FilePath -> Text -> Maybe Text
recordedProgram file rec = lookup (takeFileName file) (recordedPrograms rec)

-- | EVERY program section a record holds: @(recorded file name, its text)@.
-- The record stores the corpus verbatim, so this is a read, not a
-- reconstruction, and 'recordedProgram' is one lookup into it -- one parser for
-- both, so the "this program" and "the whole corpus" readings cannot drift.
--
-- The corpus reading is what lets a baked-source language judge a program the
-- record holds no section for (a sibling added after the mint): its sentences
-- must at least be sentences the mint SAW, in some program of the language.
recordedPrograms :: Text -> [(FilePath, Text)]
recordedPrograms rec = sections (takeWhile notBlock (drop 1 (dropWhile (/= marker) (T.lines rec))))
  where
    marker = "--- program (input) ---"
    -- The program block ends where the next record block begins.
    notBlock l = not ("--- " `T.isPrefixOf` l)
    sections [] = []
    sections (l : rest) = case sectionName l of
      Nothing -> sections rest
      Just n  ->
        let (body, more) = break (isJust . sectionName) rest
         -- The framing separates sections with a blank line, which is not part
         -- of the program (and is ignored by crystallize anyway); drop it so the
         -- text read back equals the text put in.
         in (n, T.unlines (dropWhileEnd T.null body)) : sections more
    sectionName l = T.unpack <$> (T.stripPrefix "=== program " l >>= T.stripSuffix " ===")
