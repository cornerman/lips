{-# LANGUAGE OverloadedStrings #-}

-- | The language's minted explanation, rendered for a human. The engine is
-- exact but terse; this is the only place the mint speaks plainly about what it
-- built, which mechanism it chose, and what it had to invent. Every successful
-- mint overwrites it, so it can never describe a language that is no longer
-- there.
module Lips.Generate.Readme (renderReadme) where

import           Data.Text (Text)
import qualified Data.Text as T

import Lips.Generate.Minting (Gap (..))

-- | Language name, the mint's prose, and the capabilities it found missing.
renderReadme :: Text -> Text -> [Gap] -> Text
renderReadme lang body gaps = T.unlines $
  [ "<!-- Written by `lips generate`. Every mint overwrites it; edits are lost. -->"
  , ""
  , "# The `" <> lang <> "` language"
  , ""
  , T.strip body
  ] ++ gapSection
  where
    gapSection
      | null gaps = []
      | otherwise = [ "", "## Known Gaps", "" ] ++ concat
          [ [ "### " <> gapSlug g, "", T.strip (gapBody g), "" ] | g <- gaps ]
