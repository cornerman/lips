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
  , grammarIsFrozen
  , orphanIgnores
  ) where

import           Control.Monad    (filterM)
import           Data.List        (sort)
import           Data.Maybe       (isJust)
import           Data.Text        (Text)
import qualified Data.Text        as T
import           Lips.Identity    (rulesPathIn, worldDirIn)
import           Lips.Kernel.Capture      (matchSubject)
import           Lips.Kernel.Engine.Data   (IgnoreSpec (..), MapRule (..), renderAttrPath)
import           Lips.Kernel.Lang.Store    (EngineData (..))
import           System.Directory (doesDirectoryExist, doesFileExist, listDirectory)

-- | The ignore declarations no world of the language places: (world, id,
-- subject). Empty is the sound case.
--
-- This is what keeps @ignore@ from being an escape hatch. A world may declare a
-- fact it cannot place, but only where ANOTHER world spends it: then the
-- declaration records a real asymmetry between two lowerings. A fact NO world
-- places is a word the program states and the language throws away, which is
-- the refusal it has always been, and an @ignore@ must not launder it.
--
-- It lives here rather than in the kernel's engine gate because it is a property
-- OF A LANGUAGE ACROSS ITS WORLDS: no single engine can see it, and it only
-- became checkable when one mint began writing every world at once.
orphanIgnores :: [(Text, EngineData)] -> [(Text, Text, Text)]
orphanIgnores worlds =
  [ (w, igId ig, renderAttrPath (igSubject ig))
  | (w, eng) <- worlds, ig <- edIgnores eng, not (placedSomewhere ig) ]
  where
    placedSomewhere ig = any (placesIt ig) [ r | (_, eng) <- worlds, r <- edRules eng ]
    -- The same matching a rule does, both ways round, so a family placed by a
    -- family counts: `ignore fact pkg.<name>` is placed by a rule matching
    -- `fact pkg.<name>`, and by one matching `fact pkg.htop`.
    placesIt ig r = mrKind r == igKind ig
                      && (isJust (matchSubject (mrSubject r) (igSubject ig))
                            || isJust (matchSubject (igSubject ig) (mrSubject r)))

-- | May a mint still change the shared grammar, given the worlds a language
-- already holds and the worlds a run is still going to mint (the current one
-- included)?
--
-- Frozen exactly when some committed world will NOT be minted in the rest of
-- the run: its rules were lowered from these patterns and nothing is going to
-- rewrite them, so the patterns must stay as they are. One test covers both
-- cases -- a world minted earlier in the same run is already committed and no
-- longer upcoming, so the second world of @-t a -t b@ inherits from the
-- first. A first mint, and a re-mint of every world the language holds, are
-- both free, which is why the remedy for a refused change is to name every
-- world in one call, a @-t@ each.
grammarIsFrozen :: [Text] -> [Text] -> Bool
grammarIsFrozen committed upcoming = any (`notElem` upcoming) committed

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
