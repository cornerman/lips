{-# LANGUAGE OverloadedStrings #-}

-- | Which worlds a language folder holds, answered by LOOKING: a world is a
-- subdirectory carrying this language's own @\<language\>.rules@.
--
-- Discovery rather than declaration, because a declared list can disagree with
-- the folder and a listing cannot. A list in a file would have to be written by
-- one mint and read by the next, so a hand-deleted world folder, a half-copied
-- tree or an interrupted mint would leave lips compiling a world that is not
-- there (or ignoring one that is).
--
-- The RULES are the marker, not the @.generation@ record beside them, because
-- the rules are what makes a world compilable at all while the record only says
-- how they came to be: an engine written by hand carries no record and is
-- legitimate (it is the case 'Lips.Generate.Record.stampFaults' inverts its rule
-- for), so keying on the record would make such a folder invisible. @out\/@ and
-- @artifacts\/@ are excluded for free, since neither holds a rules file.
module Lips.Language
  ( mintedWorlds
  ) where

import           Control.Monad    (filterM)
import           Data.List        (sort)
import           Data.Text        (Text)
import qualified Data.Text        as T
import           Lips.Identity    (rulesPathIn, worldDirIn)
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
               else doesFileExist (rulesPathIn dir w file)
