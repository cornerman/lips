{-# LANGUAGE OverloadedStrings #-}

-- | A world as DATA: which Nix world an engine's option paths belong to, read
-- from a @\<name\>.world@ file rather than enumerated in Haskell. The kernel
-- knows nothing about any world; lips knows only this shape, so a world nobody
-- foresaw (darwin, nix-on-droid, a house flavour) works without a lips change.
-- Design: docs\/superpowers\/specs\/2026-08-07-world-files-design.md.
--
-- The file is header lines (@key: value@) followed by @--- \<slot\> ---@
-- blocks. Both name sets are CLOSED and parsing is strict: an unknown key or
-- slot is a typo, or a file written for a lips that knows more, and either
-- must be named rather than silently dropped.
module Lips.World
  ( World (..)
  , Rung (..)
  , parseWorld
  , slotMarker
  , worldFormat
  ) where

import           Data.Maybe (fromMaybe)
import           Data.Text  (Text)
import qualified Data.Text  as T
import           Text.Read  (readMaybe)

-- | The format this binary reads. A file declaring a NEWER format is refused
-- naming both numbers: it carries structure this lips cannot honour, and
-- honouring part of it would be a silent half-read.
worldFormat :: Int
worldFormat = 1

-- | The slot a line opens, when it is a slot marker (@--- builds ---@). The one
-- authority on that syntax: 'Lips.World.Check' finds the same regions to hand
-- each slot to nix's parser, and a second reading of the fences would be a
-- second answer to "where does this slot start".
slotMarker :: Text -> Maybe Text
slotMarker l
  | "--- " `T.isPrefixOf` s = Just (T.strip (T.dropEnd 3 (T.drop 4 s)))
  | otherwise = Nothing
  where s = T.strip l

-- | One line of what @compile@ prints as the ways into a compiled directory:
-- either a nix command over one flake attribute, or a literal line (an import
-- instruction, say) whose @\<dir\>@ the printer fills.
data Rung
  = RungCmd { rgLabel :: Text, rgVerb :: Text, rgAttr :: Text, rgNote :: Text }
  | RungLine Text
  deriving (Eq, Show)

-- | Everything lips needs to mint into a world, ground against it, and build
-- its flake. Headers name the world; slots carry text lips places verbatim, so
-- a world's Nix is the world file's business and never a branch in lips.
data World = World
  { wName        :: Text        -- ^ header @world:@, the name a program targets
  , wModuleAttr  :: Text        -- ^ header @module-attr:@, e.g. @nixosModules@
  , wSchemaPin   :: Maybe Text  -- ^ header @schema-pin:@, env var holding a locked flakeref
  , wSchemaFlake :: Maybe Text  -- ^ header @schema-flake:@, the fallback flakeref
  , wClaims      :: [Text]      -- ^ header @claims:@, the places this world can host
  , wInputArgs   :: Text        -- ^ header @input-args:@, extra outputs-function args
  , wPreamble    :: Text        -- ^ slot @preamble@, the world's half of the mint prompt
  , wSchema      :: Text
    -- ^ slot @schema@: a Nix expression with two holes, @\<flakeref\>@ (the
    -- locked flake the options come from) and @\<system\>@ (which lips fills
    -- with @builtins.currentSystem@ and a pure evaluation fills with a literal).
    -- Filled in, it must evaluate to a derivation whose @$out@ IS the
    -- options.json file, so no caller knows a path inside it.
  , wInputs      :: [Text]      -- ^ slot @inputs@, flake input lines
  , wBuilds      :: [Text]      -- ^ slot @builds@, the body of the @builds@ let-binding
  , wPackages    :: Maybe Text  -- ^ slot @packages@
  , wApps        :: Maybe Text  -- ^ slot @apps@
  , wDevShells   :: Maybe Text  -- ^ slot @devShells@
  , wRungs       :: [Rung]      -- ^ slot @rungs@
  , wRaw         :: Text        -- ^ the file verbatim, for copying beside an engine and hashing
  }
  deriving (Eq, Show)

headerKeys :: [Text]
headerKeys = ["format", "world", "module-attr", "schema-pin", "schema-flake", "input-args", "claims"]

slotNames :: [Text]
slotNames = ["preamble", "schema", "inputs", "builds", "packages", "apps", "devShells", "rungs"]

-- | Parse a world file, or say exactly what is wrong with it.
parseWorld :: Text -> Either Text World
parseWorld raw = do
  let (hdrLines, slotLines) = break isMarker (T.lines raw)
  hdrs <- mapM headerOf (filter (not . blank) hdrLines)
  mapM_ (\(k, _) -> if k `elem` headerKeys then Right () else err ("unknown header key " <> k)) hdrs
  slots <- slotsOf slotLines
  mapM_ (\(s, _) -> if s `elem` slotNames then Right () else err ("unknown slot " <> s)) slots
  fmtText <- required hdrs "format"
  fmt <- maybe (err ("format is not a number: " <> fmtText)) Right
                (readMaybe (T.unpack (T.strip fmtText)) :: Maybe Int)
  if fmt > worldFormat
    then err ("this file declares format " <> tshow fmt <> "; this lips reads format "
              <> tshow worldFormat <> " \8594 upgrade lips")
    else Right ()
  name <- required hdrs "world"
  modAttr <- required hdrs "module-attr"
  preamble <- requiredSlot slots "preamble"
  schema <- requiredSlot slots "schema"
  rungs <- mapM rungOf (filter (not . blank) (slotLines' slots "rungs"))
  Right World
    { wName = name
    , wModuleAttr = modAttr
    , wSchemaPin = lookup "schema-pin" hdrs
    , wSchemaFlake = lookup "schema-flake" hdrs
    , wClaims = maybe [] T.words (lookup "claims" hdrs)
    , wInputArgs = fromMaybe "" (lookup "input-args" hdrs)
    , wPreamble = preamble
    , wSchema = schema
    , wInputs = filter (not . blank) (slotLines' slots "inputs")
    , wBuilds = slotLines' slots "builds"
    , wPackages = fmap T.unlines (lookup "packages" slots)
    , wApps = fmap T.unlines (lookup "apps" slots)
    , wDevShells = fmap T.unlines (lookup "devShells" slots)
    , wRungs = rungs
    , wRaw = raw
    }
  where
    err :: Text -> Either Text a
    err reason = Left ("world file: " <> reason)

    blank = T.null . T.strip

    isMarker = (/= Nothing) . slotMarker

    headerOf l = case T.breakOn ":" l of
      (k, v) | T.null v -> err ("header line without a colon: " <> l)
             | otherwise -> Right (T.strip k, T.strip (T.drop 1 v))

    -- Group the remaining lines under the marker that introduced them.
    slotsOf [] = Right []
    slotsOf (l : ls)
      | Just name <- slotMarker l =
          let (body, rest) = break isMarker ls
          in ((name, trimTrailing body) :) <$> slotsOf rest
      | otherwise = err ("stray line outside every slot: " <> l)

    -- The blank line before the next marker is the file's own spacing, never
    -- the slot's content: a world file reads as prose, and its Nix must not
    -- inherit that formatting.
    trimTrailing = reverse . dropWhile blank . reverse

    required hdrs k = maybe (err ("missing required header " <> k)) Right (lookup k hdrs)
    requiredSlot slots s =
      maybe (err ("missing required slot " <> s)) (Right . T.unlines) (lookup s slots)
    slotLines' slots s = fromMaybe [] (lookup s slots)

    -- Two forms, so a printed line that is not a nix command needs no fake attribute.
    rungOf l
      | "text:" `T.isPrefixOf` T.strip l = Right (RungLine (T.strip (T.drop 5 (T.strip l))))
      | otherwise = case map T.strip (T.splitOn "|" l) of
          [lbl, verb, attr, note] -> Right (RungCmd lbl verb attr note)
          _ -> err ("rung is neither 'label | verb | attr | note' nor 'text: <line>': " <> l)

    tshow :: Int -> Text
    tshow = T.pack . show
