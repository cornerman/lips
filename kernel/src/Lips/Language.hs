{-# LANGUAGE OverloadedStrings #-}

-- | Which worlds a language folder holds, answered by LOOKING: a world is a
-- subdirectory carrying this language's own @.generation@ record.
--
-- Discovery rather than declaration, because a declared list can disagree with
-- the folder and a listing cannot. A list in a file would have to be written by
-- one mint and read by the next, so a hand-deleted world folder, a half-copied
-- tree or an interrupted mint would leave lips compiling a world that is not
-- there (or ignoring one that is). The record is the right marker because it is
-- what @generate@ writes last for a world and what every reader already needs:
-- @out\/@ and @artifacts\/@ are excluded for free, since neither holds one.
module Lips.Language
  ( mintedWorlds
  ) where

import           Control.Monad    (filterM)
import           Data.List        (sort)
import           Data.Text        (Text)
import qualified Data.Text        as T
import           Lips.Identity    (generationPathIn, worldDirIn)
import           System.Directory (doesDirectoryExist, doesFileExist, listDirectory)

-- | The worlds a committed language folder holds, sorted so output order is
-- the same on every machine and in every run. A missing folder holds none.
mintedWorlds :: FilePath -> FilePath -> IO [Text]
mintedWorlds dir file = do
  there <- doesDirectoryExist dir
  if not there then pure [] else do
    entries <- listDirectory dir
    sort <$> filterM isWorld (map T.pack entries)
  where
    isWorld w = do
      d <- doesDirectoryExist (worldDirIn dir w)
      if not d then pure False
               else doesFileExist (generationPathIn (worldDirIn dir w) file)
